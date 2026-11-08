// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:convert';

import '../storage/secure_store.dart';

/// A trusted host key: type (e.g. `ssh-ed25519`) plus OpenSSH SHA-256
/// fingerprint (`SHA256:...`).
class HostKey {
  const HostKey({required this.type, required this.fingerprint});

  final String type;
  final String fingerprint;

  Map<String, dynamic> toJson() => {'type': type, 'fingerprint': fingerprint};

  factory HostKey.fromJson(Map<String, dynamic> json) => HostKey(
    type: json['type'] as String,
    fingerprint: json['fingerprint'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is HostKey &&
      other.type == type &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(type, fingerprint);
}

enum KnownHostStatus {
  /// No key stored for this host:port yet (trust on first use).
  unknown,

  /// The presented key is exactly the stored one.
  match,

  /// A key is stored and the presented one differs in type or fingerprint.
  mismatch,
}

class KnownHostCheck {
  const KnownHostCheck(this.status, {this.stored});

  final KnownHostStatus status;

  /// The previously trusted key (set for [match] and [mismatch]).
  final HostKey? stored;
}

/// Trusted host keys, one per `hostname:port`, in encrypted storage.
///
/// Hostnames are normalized (trimmed, lowercased) and nothing else: an IP
/// address and a hostname for the same server are separate entries, like
/// OpenSSH. Any different key, including a different key type, is a mismatch.
class KnownHostsStore {
  KnownHostsStore(this._store);

  static const storageKey = 'known_hosts.v1';

  final SecureStore _store;

  static String entryKey(String hostname, int port) =>
      '${hostname.trim().toLowerCase()}:$port';

  Future<Map<String, HostKey>> _load() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (k, v) => MapEntry(k, HostKey.fromJson(v as Map<String, dynamic>)),
    );
  }

  Future<void> _save(Map<String, HostKey> keys) => _store.write(
    storageKey,
    jsonEncode(keys.map((k, v) => MapEntry(k, v.toJson()))),
  );

  Future<HostKey?> get(String hostname, int port) async =>
      (await _load())[entryKey(hostname, port)];

  Future<KnownHostCheck> check(
    String hostname,
    int port,
    HostKey presented,
  ) async {
    final stored = await get(hostname, port);
    if (stored == null) return const KnownHostCheck(KnownHostStatus.unknown);
    return KnownHostCheck(
      stored == presented ? KnownHostStatus.match : KnownHostStatus.mismatch,
      stored: stored,
    );
  }

  /// Records [key] as trusted. Only call after explicit user confirmation.
  /// Refuses to overwrite a different existing key: the user must call
  /// [remove] first (host settings).
  Future<void> trust(String hostname, int port, HostKey key) async {
    final keys = await _load();
    final k = entryKey(hostname, port);
    final existing = keys[k];
    if (existing != null && existing != key) {
      throw StateError('A different host key is already trusted for $k');
    }
    keys[k] = key;
    await _save(keys);
  }

  Future<void> remove(String hostname, int port) async {
    final keys = await _load();
    if (keys.remove(entryKey(hostname, port)) != null) await _save(keys);
  }
}
