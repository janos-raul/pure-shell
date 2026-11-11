// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:pureshell/core/keys/key_repository.dart';
import 'package:pureshell/core/keys/key_service.dart';
import 'package:pureshell/core/keys/keystore_api.dart';
import 'package:pureshell/core/keys/ssh_ec_encoding.dart';
import 'package:pureshell/core/keys/ssh_key.dart';
import 'package:pureshell/core/keys/ssh_rsa_encoding.dart';
import 'package:pureshell/core/keys/windows_keystore.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/ui/keys/key_detail_screen.dart';
import 'package:pureshell/ui/keys/keys_screen.dart';

import 'fake_keystore.dart';

// ignore: implementation_imports
import 'package:dartssh2/src/hostkey/hostkey_rsa.dart';

Uint8List _unsigned(BigInt v) {
  final out = <int>[];
  while (v > BigInt.zero) {
    out.add((v & BigInt.from(0xff)).toInt());
    v >>= 8;
  }
  return Uint8List.fromList(out.reversed.toList());
}

/// What KeyCredential.RetrievePublicKey(BCryptPublicKey) returns.
Uint8List bcryptBlob(RSAPublicKey k, {int magic = 0x31415352}) {
  final e = _unsigned(k.publicExponent!);
  final n = _unsigned(k.modulus!);
  final h = ByteData(24)
    ..setUint32(0, magic, Endian.little)
    ..setUint32(4, n.length * 8, Endian.little)
    ..setUint32(8, e.length, Endian.little)
    ..setUint32(12, n.length, Endian.little);
  return Uint8List.fromList([...h.buffer.asUint8List(), ...e, ...n]);
}

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> rsaKeyPair(int bits) {
  final rnd = FortunaRandom()
    ..seed(KeyParameter(Uint8List.fromList(List.filled(32, 7))));
  final gen = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
        rnd,
      ),
    );
  final p = gen.generateKeyPair();
  return AsymmetricKeyPair(p.publicKey, p.privateKey);
}

/// RSASSA-PKCS1-v1_5 with SHA-256 over the raw data: what Windows Hello does.
Uint8List windowsSign(RSAPrivateKey key, Uint8List data) {
  final s = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(key));
  return s.generateSignature(data).bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pair = rsaKeyPair(2048);
  final message = Uint8List.fromList(utf8.encode('ssh session data'));

  group('encoding', () {
    test('BCrypt blob -> ssh-rsa blob that dartssh2 reads back', () {
      final blob = rsaPublicKeyBlobFromBcrypt(bcryptBlob(pair.publicKey));
      final decoded = SSHRsaPublicKey.decode(blob);
      expect(decoded.n, pair.publicKey.modulus);
      expect(decoded.e, pair.publicKey.publicExponent);
      expect(rsaAuthorizedKeysLine(blob, comment: 'c'), startsWith('ssh-rsa '));
      expect(rsaFingerprint(blob), startsWith('SHA256:'));
    });

    test('rsa-sha2-256 signature blob verifies with dartssh2', () {
      final blob = rsaPublicKeyBlobFromBcrypt(bcryptBlob(pair.publicKey));
      final sig = rsaSha256SignatureBlob(windowsSign(pair.privateKey, message));
      final decoded = SSHRsaSignature.decode(sig);
      expect(decoded.type, 'rsa-sha2-256');
      expect(SSHRsaPublicKey.decode(blob).verify(message, decoded), isTrue);
    });

    test('rejects other blobs and keys under 2048 bits', () {
      expect(
        () => rsaPublicKeyBlobFromBcrypt(
          bcryptBlob(pair.publicKey, magic: 0x32415352),
        ),
        throwsA(isA<SshEncodingException>()),
      );
      expect(
        () =>
            rsaPublicKeyBlobFromBcrypt(bcryptBlob(rsaKeyPair(1024).publicKey)),
        throwsA(isA<SshEncodingException>()),
      );
    });
  });

  group('WindowsKeystore + KeyService', () {
    const channel = MethodChannel('eu.pureshell.app/hello_keys');
    late MemorySecureStore store;
    late KeyService service;
    late bool supported;
    late String attestation;
    final created = <String>{};
    final calls = <String>[];

    setUp(() {
      store = MemorySecureStore();
      supported = true;
      attestation = 'success';
      created.clear();
      calls.clear();
      service = KeyService(
        WindowsKeystore(store),
        KeyRepository(store),
        random: Random(3),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            final a = call.arguments as Map?;
            switch (call.method) {
              case 'isSupported':
                return supported;
              case 'create':
                created.add(a!['alias'] as String);
                return {
                  'publicKey': bcryptBlob(pair.publicKey),
                  'attestation': attestation,
                };
              case 'exists':
                return created.contains(a!['alias']);
              case 'sign':
                return windowsSign(pair.privateKey, a!['data'] as Uint8List);
              case 'delete':
                created.remove(a!['alias']);
                return null;
            }
            return null;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('Hello key: ssh-rsa line, rsa-sha2-256 login signature', () async {
      final key = await service.generate(name: 'hello');
      expect(key.kind, KeyKind.helloRsa);
      expect(key.level, SecurityLevel.tpm);
      expect(key.isSoftware, isFalse);
      expect(key.sshType, 'ssh-rsa');
      expect(key.authAlgorithm, 'rsa-sha2-256');
      expect(key.authorizedKeysLine, startsWith('ssh-rsa AAAAB3NzaC1yc2E'));

      final blob = await service.sign(key, message);
      final sig = SSHRsaSignature.decode(blob);
      expect(sig.type, 'rsa-sha2-256');
      expect(
        SSHRsaPublicKey.decode(key.publicKeyBlob).verify(message, sig),
        isTrue,
      );
      // The private key never comes to Dart: only these calls exist.
      expect(calls.toSet(), {
        'isSupported',
        'consentAvailable',
        'create',
        'sign',
      });
    });

    test('no TPM proof: labelled Hello, not TPM', () async {
      attestation = 'notSupported';
      final key = await service.generate(name: 'vm');
      expect(key.level, SecurityLevel.hello);
    });

    test('listed while present, deleted from Windows', () async {
      final key = await service.generate(name: 'k');
      expect(await service.presentAliases(), {key.signAlias});
      await service.delete(key);
      expect(created, isEmpty);
      expect(await service.presentAliases(), isEmpty);
    });

    test('Hello not set up: software Ed25519 fallback', () async {
      supported = false;
      final key = await service.generate(name: 'soft');
      expect(key.kind, KeyKind.softwareEd25519);
      expect(calls, isNot(contains('create')));
    });

    test('cancelled prompt maps to cancelled', () async {
      final key = await service.generate(name: 'k');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => throw PlatformException(code: 'cancelled'),
          );
      expect(
        () => service.sign(key, message),
        throwsA(
          isA<KeystoreException>().having(
            (e) => e.kind,
            'kind',
            KeystoreErrorKind.cancelled,
          ),
        ),
      );
    });
  });

  testWidgets('a Hello key shows the Windows Hello reset warning', (t) async {
    final store = MemorySecureStore();
    final key = SshKey(
      id: 'k1',
      name: 'hello',
      kind: KeyKind.helloRsa,
      level: SecurityLevel.tpm,
      publicKey: rsaPublicKeyBlobFromBcrypt(bcryptBlob(pair.publicKey)),
      createdAt: DateTime.utc(2026, 11, 11),
    );
    await t.pumpWidget(
      MaterialApp(
        home: KeyDetailScreen(
          keyService: KeyService(FakeKeystore(), KeyRepository(store)),
          sshKey: key,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text(helloKeyNotice), findsOneWidget);
    expect(find.text('TPM + Hello'), findsOneWidget);
    expect(helloKeyNotice, contains('permanently lost'));
  });
}
