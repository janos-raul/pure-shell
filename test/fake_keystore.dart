// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:pureshell/core/keys/keystore_api.dart';

Uint8List _derInt(BigInt v) {
  var bytes = <int>[];
  var x = v;
  while (x > BigInt.zero) {
    bytes.add((x & BigInt.from(0xff)).toInt());
    x >>= 8;
  }
  bytes = bytes.reversed.toList();
  if (bytes.first & 0x80 != 0) bytes = [0, ...bytes];
  return Uint8List.fromList([0x02, bytes.length, ...bytes]);
}

/// A Keystore stand-in with real P-256 keys in memory, so signatures can be
/// verified end to end. (The real one never lets keys out.)
class FakeKeystore implements KeystoreApi {
  bool secureLock = true;
  SecurityLevel level = SecurityLevel.tee;
  bool cancelNext = false;
  bool failSign = false;
  int sdkInt = 35;

  /// Levels the "live" Keystore reports, by alias (default: [level]).
  final liveLevels = <String, SecurityLevel>{};
  final _createdLevels = <String, SecurityLevel>{};
  final ec = <String, ECPrivateKey>{};
  final points = <String, Uint8List>{};
  final wrapKeys = <String>{};
  final calls = <String>[];
  final _rnd = FortunaRandom()
    ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i + 3))));

  @override
  Future<KeystoreCapabilities> capabilities() async => KeystoreCapabilities(
    secureLockScreen: secureLock,
    canAuthenticate: secureLock,
    sdkInt: sdkInt,
  );

  @override
  Future<GeneratedKey> generateKey(String alias) async {
    calls.add('generateKey');
    final gen = ECKeyGenerator()
      ..init(
        ParametersWithRandom(
          ECKeyGeneratorParameters(ECCurve_secp256r1()),
          _rnd,
        ),
      );
    final pair = gen.generateKeyPair();
    ec[alias] = pair.privateKey;
    points[alias] = pair.publicKey.Q!.getEncoded(false);
    _createdLevels[alias] = level;
    return GeneratedKey(
      level: level,
      publicPoint: pair.publicKey.Q!.getEncoded(false),
    );
  }

  @override
  Future<Uint8List> sign(
    String alias,
    Uint8List data, {
    String title = '',
    String? subtitle,
  }) async {
    if (cancelNext) {
      cancelNext = false;
      throw const KeystoreException(KeystoreErrorKind.cancelled);
    }
    if (failSign) throw const KeystoreException(KeystoreErrorKind.lockout);
    final signer = ECDSASigner(SHA256Digest())
      ..init(true, ParametersWithRandom(PrivateKeyParameter(ec[alias]!), _rnd));
    final sig = signer.generateSignature(data) as ECSignature;
    final body = [..._derInt(sig.r), ..._derInt(sig.s)];
    return Uint8List.fromList([0x30, body.length, ...body]);
  }

  @override
  Future<SecurityLevel> generateWrapKey(String alias) async {
    wrapKeys.add(alias);
    _createdLevels[alias] = level;
    return level;
  }

  @override
  Future<({Uint8List iv, Uint8List data})> wrap(
    String alias,
    Uint8List data,
  ) async {
    if (cancelNext) {
      cancelNext = false;
      throw const KeystoreException(KeystoreErrorKind.cancelled);
    }
    return (
      iv: Uint8List(12),
      data: Uint8List.fromList(data.map((b) => b ^ 0x5a).toList()),
    );
  }

  @override
  Future<Uint8List> unwrap(String alias, Uint8List iv, Uint8List data) async {
    if (cancelNext) {
      cancelNext = false;
      throw const KeystoreException(KeystoreErrorKind.cancelled);
    }
    // Like the real platform channel: a read-only view.
    return Uint8List.fromList(data.map((b) => b ^ 0x5a).toList())
        .asUnmodifiableView();
  }

  @override
  Future<void> deleteKey(String alias) async {
    ec.remove(alias);
    wrapKeys.remove(alias);
  }

  @override
  Future<List<String>> listKeys() async => [...ec.keys, ...wrapKeys];

  @override
  Future<SecurityLevel> securityLevel(String alias) async {
    if (!ec.containsKey(alias) && !wrapKeys.contains(alias)) {
      throw const KeystoreException(KeystoreErrorKind.failed);
    }
    return liveLevels[alias] ?? _createdLevels[alias] ?? level;
  }

  @override
  Future<Uint8List> publicKey(String alias) async => points[alias]!;

  @override
  Future<void> authenticate({String title = '', String? subtitle}) async {}

  @override
  Future<void> cancelPrompt() async {}
}
