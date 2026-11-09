// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:convert';
import 'dart:typed_data';

import 'keystore_api.dart';
import 'ssh_ec_encoding.dart' as ec;
import 'ssh_ed25519_encoding.dart';

enum KeyKind {
  /// EC P-256 key inside the Android Keystore. Never leaves it.
  hardwareEcdsa,

  /// Ed25519 key made in Dart for phones without secure hardware; its seed is
  /// stored encrypted with a Keystore AES key that needs the user for every use.
  softwareEd25519,
}

class WrappedSeed {
  const WrappedSeed({required this.iv, required this.data});

  final Uint8List iv;
  final Uint8List data;

  Map<String, dynamic> toJson() => {
    'iv': base64.encode(iv),
    'data': base64.encode(data),
  };

  factory WrappedSeed.fromJson(Map<String, dynamic> j) => WrappedSeed(
    iv: base64.decode(j['iv'] as String),
    data: base64.decode(j['data'] as String),
  );
}

/// A key the user created in the app. Contains no private key material: for
/// hardware keys that is inside the Keystore, for software keys only an
/// encrypted blob that the Keystore has to unwrap.
class SshKey {
  const SshKey({
    required this.id,
    required this.name,
    required this.kind,
    required this.level,
    required this.publicKey,
    required this.createdAt,
    this.comment = ec.defaultKeyComment,
    this.wrapped,
  });

  final String id;
  final String name;
  final KeyKind kind;

  /// Where the key lives (StrongBox / TEE / Software), as reported when it
  /// was created.
  final SecurityLevel level;

  /// Uncompressed P-256 point (hardware) or the 32-byte Ed25519 key.
  final Uint8List publicKey;
  final DateTime createdAt;
  final String comment;
  final WrappedSeed? wrapped;

  bool get isSoftware => kind == KeyKind.softwareEd25519;

  /// Keystore alias of the signing key (hardware) ...
  String get signAlias => 'pureshell_$id';

  /// ... or of the AES wrap key (software).
  String get wrapAlias => 'pureshell_${id}_wrap';

  /// The Keystore alias that holds this key's secret.
  String get keystoreAlias => isSoftware ? wrapAlias : signAlias;

  String get sshType => isSoftware ? ed25519Type : ec.ecdsaP256Type;

  Uint8List get publicKeyBlob => isSoftware
      ? ed25519PublicKeyBlob(publicKey)
      : ec.ecdsaP256PublicKeyBlob(publicKey);

  String get authorizedKeysLine => isSoftware
      ? ed25519AuthorizedKeysLine(publicKey, comment: comment)
      : ec.authorizedKeysLine(publicKey, comment: comment);

  String get fingerprint => isSoftware
      ? ed25519Fingerprint(publicKey)
      : ec.publicKeyFingerprint(publicKey);

  SshKey copyWith({String? name, String? comment}) => SshKey(
    id: id,
    name: name ?? this.name,
    kind: kind,
    level: level,
    publicKey: publicKey,
    createdAt: createdAt,
    comment: comment ?? this.comment,
    wrapped: wrapped,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'level': level.name,
    'publicKey': base64.encode(publicKey),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'comment': comment,
    if (wrapped != null) 'wrapped': wrapped!.toJson(),
  };

  factory SshKey.fromJson(Map<String, dynamic> j) => SshKey(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: KeyKind.values.byName(j['kind'] as String),
    level: SecurityLevel.values.byName(j['level'] as String),
    publicKey: base64.decode(j['publicKey'] as String),
    createdAt: DateTime.parse(j['createdAt'] as String),
    comment: (j['comment'] as String?) ?? ec.legacyKeyComment,
    wrapped: j['wrapped'] == null
        ? null
        : WrappedSeed.fromJson(j['wrapped'] as Map<String, dynamic>),
  );
}
