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

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:pureshell/core/keys/key_repository.dart';
import 'package:pureshell/core/keys/key_service.dart';
import 'package:pureshell/core/keys/keystore_api.dart';
import 'package:pureshell/core/keys/ssh_ec_encoding.dart';
import 'package:pureshell/core/keys/ssh_key.dart';
import 'package:pureshell/core/storage/secure_store.dart';

import 'fake_keystore.dart';

// ignore: implementation_imports
import 'package:dartssh2/src/hostkey/hostkey_ecdsa.dart';

void main() {
  late FakeKeystore keystore;
  late MemorySecureStore store;
  late KeyService service;

  setUp(() {
    keystore = FakeKeystore();
    store = MemorySecureStore();
    service = KeyService(keystore, KeyRepository(store), random: Random(7));
  });

  final message = Uint8List.fromList(utf8.encode('challenge'));

  test('hardware key: stored with its level, signature verifies', () async {
    final key = await service.generate(name: 'Phone key');
    expect(key.kind, KeyKind.hardwareEcdsa);
    expect(key.level, SecurityLevel.tee);
    expect(key.isSoftware, isFalse);
    expect(key.comment, 'pure-shell');
    expect(key.authorizedKeysLine, startsWith('ecdsa-sha2-nistp256 AAAA'));
    expect(key.authorizedKeysLine, endsWith(' pure-shell'));
    expect(key.fingerprint, startsWith('SHA256:'));

    final blob = await service.sign(key, message);
    final verifier = SSHEcdsaPublicKey.decode(key.publicKeyBlob);
    expect(verifier.verify(message, SSHEcdsaSignature.decode(blob)), isTrue);

    expect((await service.list()).single.id, key.id);
  });

  test('StrongBox is reported as such', () async {
    keystore.level = SecurityLevel.strongBox;
    expect((await service.generate(name: 'k')).level, SecurityLevel.strongBox);
  });

  test('no screen lock: clear error, nothing created', () async {
    keystore.secureLock = false;
    await expectLater(
      service.generate(name: 'k'),
      throwsA(
        isA<KeystoreException>().having(
          (e) => e.kind,
          'kind',
          KeystoreErrorKind.noScreenLock,
        ),
      ),
    );
    expect(keystore.calls, isEmpty);
    expect(await service.list(), isEmpty);
    expect(
      const KeystoreException(KeystoreErrorKind.noScreenLock).message,
      'Set a screen lock to create keys.',
    );
  });

  test('software key only when the Keystore itself reports SOFTWARE', () async {
    keystore.level = SecurityLevel.software;
    final key = await service.generate(name: 'soft');
    expect(key.isSoftware, isTrue);
    expect(key.kind, KeyKind.softwareEd25519);
    expect(key.sshType, 'ssh-ed25519');
    // The software-backed EC key that was tried first is gone.
    expect(keystore.ec, isEmpty);
    expect(keystore.wrapKeys, {key.wrapAlias});

    final blob = await service.sign(key, message);
    // string "ssh-ed25519" | string signature(64)
    final sig = blob.sublist(4 + 11 + 4);
    expect(sig.length, 64);
    final verifyKey = nacl.VerifyKey(key.publicKey);
    expect(
      () => verifyKey.verify(signature: nacl.Signature(sig), message: message),
      returnsNormally,
    );
  });

  test('hardware is never replaced by software when available', () async {
    final key = await service.generate(name: 'hw');
    expect(key.isSoftware, isFalse);
    expect(keystore.wrapKeys, isEmpty);
  });

  test('forced software mode skips the hardware attempt', () async {
    service = KeyService(
      keystore,
      KeyRepository(store),
      softwareOnly: true,
      random: Random(7),
    );
    final key = await service.generate(name: 'forced');
    expect(key.isSoftware, isTrue);
    expect(keystore.calls, isNot(contains('generateKey')));
  });

  test('cancelling the software key prompt leaves nothing behind', () async {
    keystore.level = SecurityLevel.software;
    keystore.cancelNext = true; // wrap() asks the user
    await expectLater(
      service.generate(name: 'soft'),
      throwsA(
        isA<KeystoreException>().having(
          (e) => e.kind,
          'kind',
          KeystoreErrorKind.cancelled,
        ),
      ),
    );
    expect(keystore.wrapKeys, isEmpty);
    expect(await service.list(), isEmpty);
  });

  test('a cancelled signing prompt surfaces as cancelled', () async {
    final key = await service.generate(name: 'k');
    keystore.cancelNext = true;
    await expectLater(
      service.sign(key, message),
      throwsA(
        isA<KeystoreException>().having(
          (e) => e.kind,
          'kind',
          KeystoreErrorKind.cancelled,
        ),
      ),
    );
  });

  test('delete removes the Keystore entry and the metadata', () async {
    final hw = await service.generate(name: 'hw');
    expect(keystore.ec, isNotEmpty);
    await service.delete(hw);
    expect(keystore.ec, isEmpty);
    expect(await service.list(), isEmpty);

    keystore.level = SecurityLevel.software;
    final sw = await service.generate(name: 'sw');
    await service.delete(sw);
    expect(keystore.wrapKeys, isEmpty);
    expect(await service.list(), isEmpty);
  });

  test('stored metadata holds no private material', () async {
    keystore.level = SecurityLevel.software;
    final key = await service.generate(name: 'soft');
    final raw = store.data[KeyRepository.storageKey]!;
    expect(raw, isNot(contains('private')));
    // The seed is only present wrapped: unwrapping needs the Keystore.
    final back = SshKey.fromJson(
      (jsonDecode(raw) as List).single as Map<String, dynamic>,
    );
    expect(back.publicKey, key.publicKey);
    expect(back.wrapped, isNotNull);
  });

  test('rename updates the name and comment, not the key', () async {
    final key = await service.generate(name: 'a');
    await service.rename(key, name: 'b', comment: 'work phone');
    final k = (await service.list()).single;
    expect(k.name, 'b');
    expect(k.authorizedKeysLine, endsWith(' work phone'));
    expect(k.publicKey, key.publicKey);
  });

  group('the comment of existing keys', () {
    Future<Map<String, dynamic>> storedJson() async {
      final key = await service.generate(name: 'old');
      return Map<String, dynamic>.from(key.toJson());
    }

    test('a key made before the rename keeps its comment', () async {
      final json = await storedJson()
        ..['comment'] = 'pureshell';
      final back = SshKey.fromJson(json);
      expect(back.comment, 'pureshell');
      expect(back.authorizedKeysLine, endsWith(' pureshell'));
      // ... also after being saved again.
      expect(SshKey.fromJson(back.toJson()).comment, 'pureshell');
    });

    test('a stored key with no comment at all keeps the old default', () async {
      final json = await storedJson()
        ..remove('comment');
      expect(SshKey.fromJson(json).comment, 'pureshell');
      expect(legacyKeyComment, 'pureshell');
    });

    test('a comment the user chose is never touched', () async {
      final json = await storedJson()
        ..['comment'] = 'work phone';
      expect(SshKey.fromJson(json).comment, 'work phone');
    });

    test('only new keys get pure-shell', () async {
      final key = await service.generate(name: 'new');
      expect(key.comment, 'pure-shell');
      expect(defaultKeyComment, 'pure-shell');
    });
  });

  test('keys carry nothing personal by default', () async {
    final key = await service.generate(name: 'x');
    expect(key.authorizedKeysLine.split(' ').last, 'pure-shell');
    expect(defaultKeyComment, 'pure-shell');
  });

  test(
    'emulator switch keeps a software-level EC key, labelled honestly',
    () async {
      keystore.level = SecurityLevel.software;
      service = KeyService(
        keystore,
        KeyRepository(store),
        keepSoftwareKeystoreKeys: true,
        random: Random(7),
      );
      final key = await service.generate(name: 'emu');
      expect(key.kind, KeyKind.hardwareEcdsa);
      expect(key.level, SecurityLevel.software);
      expect(keystore.ec, isNotEmpty);
      expect(keystore.wrapKeys, isEmpty);
      final blob = await service.sign(key, Uint8List.fromList([1, 2, 3]));
      expect(blob, isNotEmpty);
    },
  );

  test('without the switch the flag is off', () {
    expect(allowSoftwareKeystore, isFalse);
    expect(forceSoftwareKeys, isFalse);
  });

  group('security level', () {
    test(
      'is stored in the encrypted metadata when the key is created',
      () async {
        keystore.level = SecurityLevel.strongBox;
        final key = await service.generate(name: 'k');
        final raw = store.data[KeyRepository.storageKey]!;
        expect((jsonDecode(raw) as List).single['level'], 'strongBox');
        // A new service instance (a later app run) reads it back.
        final later = KeyService(keystore, KeyRepository(store));
        expect((await later.list()).single.level, SecurityLevel.strongBox);
        expect(key.level, SecurityLevel.strongBox);
      },
    );

    test('shown from the stored value when the live one agrees', () async {
      final key = await service.generate(name: 'k');
      expect(await service.displayLevel(key), SecurityLevel.tee);
    });

    test('API 31+: a different live value wins', () async {
      final key = await service.generate(name: 'k'); // stored: tee
      keystore.liveLevels[key.signAlias] = SecurityLevel.software;
      expect(await service.displayLevel(key), SecurityLevel.software);
      keystore.liveLevels[key.signAlias] = SecurityLevel.strongBox;
      expect(await service.displayLevel(key), SecurityLevel.strongBox);
    });

    test(
      'API 30 cannot tell StrongBox from TEE, so the stored value stands',
      () async {
        keystore.level = SecurityLevel.strongBox;
        final key = await service.generate(name: 'k');
        keystore.sdkInt = 30;
        keystore.liveLevels[key.signAlias] = SecurityLevel.tee;
        expect(await service.displayLevel(key), SecurityLevel.strongBox);
      },
    );

    test(
      'a key the Keystore no longer has falls back to the stored value',
      () async {
        final key = await service.generate(name: 'k');
        keystore.ec.remove(key.signAlias);
        expect(await service.displayLevel(key), SecurityLevel.tee);
      },
    );

    test('software keys keep their own level', () async {
      keystore.level = SecurityLevel.software;
      final key = await service.generate(name: 'soft');
      expect(await service.displayLevel(key), SecurityLevel.software);
    });
  });
}
