// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:convert';

import 'package:flutter/services.dart';

import '../storage/secure_store.dart';
import 'keystore_api.dart';
import 'software_keystore.dart';
import 'ssh_key.dart' show KeyKind;
import 'ssh_rsa_encoding.dart';

/// SPIKE: the Windows [KeystoreApi].
///
/// - Signing keys are Windows Hello key credentials (native bridge,
///   `windows/runner/hello_keystore.cpp`): RSA-2048 held by Windows, TPM-backed
///   when the machine has a TPM, Windows Hello for every signature. The private
///   key never reaches Dart.
/// - When Windows Hello is not set up, [capabilities] reports
///   `hardwareKeys: false` and KeyService falls back to the clearly labelled
///   software Ed25519 key, whose wrap operations go to [SoftwareKeystore].
class WindowsKeystore implements KeystoreApi {
  WindowsKeystore(SecureStore store, {MethodChannel? channel})
    : _store = store,
      _software = SoftwareKeystore(store),
      _channel = channel ?? const MethodChannel('eu.pureshell.app/hello_keys');

  final SecureStore _store;
  final SoftwareKeystore _software;
  final MethodChannel _channel;

  /// Windows cannot list key credentials; we remember our aliases.
  static const _indexKey = 'helloKeystore.aliases';

  Future<List<String>> _index() async {
    final raw = await _store.read(_indexKey);
    return raw == null ? [] : (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> _saveIndex(List<String> a) =>
      _store.write(_indexKey, jsonEncode(a));

  Future<T?> _call<T>(
    String method, [
    Map<String, Object?>? args,
    bool prompts = false,
  ]) async {
    if (prompts) PromptTracker.active.value++;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw KeystoreException.fromCode(e.code);
    } on MissingPluginException {
      throw const KeystoreException(KeystoreErrorKind.unavailable);
    } finally {
      if (prompts) PromptTracker.active.value--;
    }
  }

  @override
  Future<KeystoreCapabilities> capabilities() async {
    Future<bool> ask(String method) async {
      try {
        return await _call<bool>(method) ?? false;
      } on KeystoreException {
        return false;
      }
    }

    // secureLockScreen: key creation is allowed either way (software keys
    // without Hello). canAuthenticate: Windows Hello user verification, for
    // the app lock.
    return KeystoreCapabilities(
      secureLockScreen: true,
      canAuthenticate: await ask('consentAvailable'),
      hardwareKeys: await ask('isSupported'),
    );
  }

  @override
  Future<GeneratedKey> generateKey(String alias) async {
    final m = await _call<Map<Object?, Object?>>('create', {
      'alias': alias,
    }, true);
    final index = await _index();
    if (!index.contains(alias)) await _saveIndex([...index, alias]);
    return GeneratedKey(
      kind: KeyKind.helloRsa,
      // Only a successful TPM attestation proves the key is in the TPM.
      level: m!['attestation'] == 'success'
          ? SecurityLevel.tpm
          : SecurityLevel.hello,
      publicPoint: rsaPublicKeyBlobFromBcrypt(m['publicKey'] as Uint8List),
    );
  }

  @override
  Future<SecurityLevel> securityLevel(String alias) async =>
      // Not re-attested; KeyService shows the level stored at creation.
      SecurityLevel.hello;

  @override
  Future<Uint8List> publicKey(String alias) async => rsaPublicKeyBlobFromBcrypt(
    (await _call<Uint8List>('publicKey', {'alias': alias}))!,
  );

  @override
  Future<Uint8List> sign(
    String alias,
    Uint8List data, {
    String title = 'Use your key',
    String? subtitle,
  }) async =>
      (await _call<Uint8List>('sign', {'alias': alias, 'data': data}, true))!;

  @override
  Future<void> deleteKey(String alias) async {
    final index = await _index();
    if (index.remove(alias)) {
      await _call<void>('delete', {'alias': alias});
      await _saveIndex(index);
    } else {
      await _software.deleteKey(alias);
    }
  }

  @override
  Future<List<String>> listKeys() async {
    final present = <String>[];
    for (final alias in await _index()) {
      try {
        if (await _call<bool>('exists', {'alias': alias}) == true) {
          present.add(alias);
        }
      } on KeystoreException {
        // unknown: leave it out, like a missing key
      }
    }
    return [...present, ...await _software.listKeys()];
  }

  @override
  Future<SecurityLevel> generateWrapKey(String alias) =>
      _software.generateWrapKey(alias);

  @override
  Future<({Uint8List iv, Uint8List data})> wrap(String alias, Uint8List data) =>
      _software.wrap(alias, data);

  @override
  Future<Uint8List> unwrap(String alias, Uint8List iv, Uint8List data) =>
      _software.unwrap(alias, iv, data);

  /// Windows Hello user verification over the app window (the app lock).
  @override
  Future<void> authenticate({
    String title = 'Unlock Pure-Shell',
    String? subtitle,
  }) => _call<void>('authenticate', {'message': title}, true);

  @override
  Future<void> cancelPrompt() async {}
}
