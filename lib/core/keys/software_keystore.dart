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

import 'package:pointycastle/export.dart';

import '../storage/secure_store.dart';
import 'keystore_api.dart';

/// EXPERIMENTAL STUB for the Windows build: a SOFTWARE-ONLY [KeystoreApi].
///
/// - No hardware keys: [generateKey] always fails, so [KeyService] must run
///   with `softwareOnly: true` (the same Ed25519 "software key" path phones
///   without secure hardware use).
/// - The AES-256-GCM wrap key for that path is random bytes kept in the
///   [SecureStore] (flutter_secure_storage on Windows: AES-GCM files under
///   Roaming %APPDATA%, their key in Windows Credential Manager, i.e. tied to
///   the Windows user account). It is NOT in a TPM and NOT bound to user
///   presence.
/// - No prompts: wrap/unwrap/authenticate never ask the user. Any process
///   running as the same Windows user can read the wrapped seed.
///
/// To be replaced by a CNG / NCrypt (Microsoft Platform Crypto Provider)
/// bridge with Windows Hello (UserConsentVerifier) before any release.
class SoftwareKeystore implements KeystoreApi {
  SoftwareKeystore(this._store, {Random? random})
    : _random = random ?? Random.secure();

  final SecureStore _store;
  final Random _random;

  static const _indexKey = 'softwareKeystore.aliases';
  static String _entry(String alias) => 'softwareKeystore.key.$alias';

  Future<List<String>> _index() async {
    final raw = await _store.read(_indexKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> _saveIndex(List<String> aliases) =>
      _store.write(_indexKey, jsonEncode(aliases));

  Future<Uint8List> _key(String alias) async {
    final raw = await _store.read(_entry(alias));
    if (raw == null) {
      throw const KeystoreException(KeystoreErrorKind.keyInvalid);
    }
    return base64Decode(raw);
  }

  Uint8List _bytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  GCMBlockCipher _gcm(bool encrypt, Uint8List key, Uint8List iv) =>
      GCMBlockCipher(AESEngine())..init(
        encrypt,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
      );

  @override
  Future<KeystoreCapabilities> capabilities() async =>
      // secureLockScreen: true only so key creation is allowed; nothing here
      // is protected by a lock screen. canAuthenticate: no prompt exists.
      const KeystoreCapabilities(
        secureLockScreen: true,
        canAuthenticate: false,
      );

  @override
  Future<GeneratedKey> generateKey(String alias) =>
      throw const KeystoreException(KeystoreErrorKind.unavailable);

  @override
  Future<SecurityLevel> securityLevel(String alias) async =>
      SecurityLevel.software;

  @override
  Future<Uint8List> publicKey(String alias) =>
      throw const KeystoreException(KeystoreErrorKind.unavailable);

  @override
  Future<Uint8List> sign(
    String alias,
    Uint8List data, {
    String title = 'Use your key',
    String? subtitle,
  }) => throw const KeystoreException(KeystoreErrorKind.unavailable);

  @override
  Future<void> deleteKey(String alias) async {
    await _store.delete(_entry(alias));
    final index = await _index();
    if (index.remove(alias)) await _saveIndex(index);
  }

  @override
  Future<List<String>> listKeys() => _index();

  @override
  Future<SecurityLevel> generateWrapKey(String alias) async {
    final index = await _index();
    if (index.contains(alias)) {
      throw const KeystoreException(KeystoreErrorKind.exists);
    }
    await _store.write(_entry(alias), base64Encode(_bytes(32)));
    await _saveIndex([...index, alias]);
    return SecurityLevel.software;
  }

  @override
  Future<({Uint8List iv, Uint8List data})> wrap(
    String alias,
    Uint8List data,
  ) async {
    final iv = _bytes(12);
    final out = _gcm(true, await _key(alias), iv).process(data);
    return (iv: iv, data: out);
  }

  @override
  Future<Uint8List> unwrap(String alias, Uint8List iv, Uint8List data) async {
    try {
      return _gcm(false, await _key(alias), iv).process(data);
    } on InvalidCipherTextException {
      throw const KeystoreException(KeystoreErrorKind.keyInvalid);
    }
  }

  @override
  Future<void> authenticate({
    String title = 'Unlock Pure-Shell',
    String? subtitle,
  }) => throw const KeystoreException(KeystoreErrorKind.unavailable);

  @override
  Future<void> cancelPrompt() async {}
}
