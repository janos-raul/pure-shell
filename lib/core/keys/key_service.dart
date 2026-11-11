// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:math';

import 'package:pinenacl/ed25519.dart';

import 'key_repository.dart';
import 'keystore_api.dart';
import 'ssh_ec_encoding.dart';
import 'ssh_ed25519_encoding.dart';
import 'ssh_rsa_encoding.dart';
import 'ssh_key.dart';

/// Debug/test switch for emulators: keep an EC key even when the Keystore
/// reports SOFTWARE (emulators have no secure hardware), so the real
/// Keystore/BiometricPrompt signing path can be tested. The key is still
/// shown with its honest "Software" level. Compile-time only.
const allowSoftwareKeystore = bool.fromEnvironment(
  'PURESHELL_ALLOW_SOFTWARE_KEYSTORE',
);

/// Debug/test switch to exercise the software-key path on a phone that does
/// have secure hardware. Compile-time only (`--dart-define`), never a
/// runtime option.
const forceSoftwareKeys = bool.fromEnvironment('PURESHELL_FORCE_SOFTWARE_KEYS');

/// Creating, using and deleting keys. Private key material stays in the
/// Keystore; this class only ever sees public keys and signatures (and, for
/// the software fallback, a seed for the duration of one signature).
class KeyService {
  KeyService(
    this._keystore,
    this._repo, {
    this.softwareOnly = forceSoftwareKeys,
    this.keepSoftwareKeystoreKeys = allowSoftwareKeystore,
    Random? random,
  }) : _random = random ?? Random.secure();

  final KeystoreApi _keystore;
  final KeyRepository _repo;
  final bool softwareOnly;
  final bool keepSoftwareKeystoreKeys;
  final Random _random;

  Future<KeystoreCapabilities> capabilities() => _keystore.capabilities();

  Future<List<SshKey>> list() => _repo.list();

  Future<SshKey?> get(String id) => _repo.get(id);

  Future<bool> lossNoticeShown() => _repo.lossNoticeShown();

  Future<void> markLossNoticeShown() => _repo.markLossNoticeShown();

  /// The security level to show for [key].
  ///
  /// The level is stored in the key's encrypted metadata when the key is
  /// created and shown from there. On Android 12+ (API 31), where the Keystore
  /// reports it authoritatively, it is compared with the live value; if they
  /// disagree the live one is shown. Nothing is logged either way. On API 30
  /// the platform cannot tell StrongBox from TEE later, so the stored value
  /// stands.
  Future<SecurityLevel> displayLevel(SshKey key) async {
    if (key.isSoftware) return key.level;
    try {
      final caps = await _keystore.capabilities();
      if (caps.sdkInt < 31) return key.level;
      return await _keystore.securityLevel(key.signAlias);
    } on KeystoreException {
      return key.level; // e.g. the key no longer exists
    }
  }

  /// Dismisses the fingerprint prompt if one is showing.
  Future<void> dismissPrompt() => _keystore.cancelPrompt();

  String _newId() => List.generate(
    8,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  /// Creates a key. Hardware key whenever the phone has secure hardware (the
  /// Keystore tries StrongBox first, then the TEE); only when the Keystore
  /// itself reports SOFTWARE is the Ed25519 software key used instead.
  ///
  /// Throws [KeystoreException] (noScreenLock if the phone has no screen lock).
  Future<SshKey> generate({
    required String name,
    String comment = defaultKeyComment,
  }) async {
    final caps = await _keystore.capabilities();
    if (!caps.secureLockScreen) {
      throw const KeystoreException(KeystoreErrorKind.noScreenLock);
    }
    final id = _newId();
    final base = SshKey(
      id: id,
      name: name.trim(),
      kind: KeyKind.hardwareEcdsa,
      level: SecurityLevel.software,
      publicKey: Uint8List(0),
      createdAt: DateTime.now().toUtc(),
      comment: comment.trim(),
    );

    if (!softwareOnly && caps.hardwareKeys) {
      final generated = await _keystore.generateKey(base.signAlias);
      if (generated.level != SecurityLevel.software ||
          keepSoftwareKeystoreKeys) {
        final key = SshKey(
          id: id,
          name: base.name,
          kind: generated.kind,
          level: generated.level,
          publicKey: generated.publicPoint,
          createdAt: base.createdAt,
          comment: base.comment,
        );
        await _repo.upsert(key);
        return key;
      }
      // No secure hardware: throw the software-backed EC key away.
      await _keystore.deleteKey(base.signAlias);
    }
    return _generateSoftware(base);
  }

  Future<SshKey> _generateSoftware(SshKey base) async {
    final seed = Uint8List.fromList(
      List.generate(32, (_) => _random.nextInt(256)),
    );
    try {
      await _keystore.generateWrapKey(base.wrapAlias);
      final WrappedSeedParts parts;
      try {
        final w = await _keystore.wrap(base.wrapAlias, seed);
        parts = (iv: w.iv, data: w.data);
      } catch (_) {
        await _keystore.deleteKey(base.wrapAlias); // cancelled: leave nothing
        rethrow;
      }
      final publicKey = Uint8List.fromList(
        SigningKey.fromSeed(seed).verifyKey.asTypedList,
      );
      final key = SshKey(
        id: base.id,
        name: base.name,
        kind: KeyKind.softwareEd25519,
        level: SecurityLevel.software,
        publicKey: publicKey,
        createdAt: base.createdAt,
        comment: base.comment,
        wrapped: WrappedSeed(iv: parts.iv, data: parts.data),
      );
      await _repo.upsert(key);
      return key;
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  /// Signs [data] after the user authenticates. Returns the SSH signature
  /// blob for [SshKey.sshType]. Throws [KeystoreException].
  Future<Uint8List> sign(
    SshKey key,
    Uint8List data, {
    String title = 'Use your key',
    String? subtitle,
  }) async {
    if (!key.isSoftware) {
      final sig = await _keystore.sign(
        key.signAlias,
        data,
        title: title,
        subtitle: subtitle,
      );
      // Android: DER ECDSA. Windows Hello: raw RSASSA-PKCS1-v1_5/SHA-256
      // (Windows hashes the data itself).
      return key.kind == KeyKind.helloRsa
          ? rsaSha256SignatureBlob(sig)
          : sshSignatureFromDer(sig);
    }
    final w = key.wrapped!;
    // The platform channel hands back a read-only view; keep our own copy so
    // it can be wiped after use.
    final seed = Uint8List.fromList(
      await _keystore.unwrap(key.wrapAlias, w.iv, w.data),
    );
    try {
      final signature = SigningKey.fromSeed(seed).sign(data).signature;
      return ed25519SignatureBlob(Uint8List.fromList(signature));
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  /// Deletes the key for good: from the Keystore first, then the metadata.
  Future<void> delete(SshKey key) async {
    await _keystore.deleteKey(key.keystoreAlias);
    await _repo.remove(key.id);
  }

  Future<void> rename(SshKey key, {String? name, String? comment}) =>
      _repo.upsert(key.copyWith(name: name, comment: comment));

  /// Aliases the Keystore holds that belong to one of our keys.
  Future<Set<String>> presentAliases() async =>
      (await _keystore.listKeys()).toSet();
}

typedef WrappedSeedParts = ({Uint8List iv, Uint8List data});
