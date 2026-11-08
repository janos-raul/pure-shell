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
import 'ssh_key.dart';

/// Metadata of the user's keys in encrypted storage. No private key material.
class KeyRepository {
  KeyRepository(this._store);

  static const storageKey = 'keys.v1';

  final SecureStore _store;

  Future<List<SshKey>> list() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => SshKey.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SshKey?> get(String id) async {
    for (final k in await list()) {
      if (k.id == id) return k;
    }
    return null;
  }

  Future<void> _save(List<SshKey> keys) => _store.write(
    storageKey,
    jsonEncode(keys.map((k) => k.toJson()).toList()),
  );

  Future<void> upsert(SshKey key) async {
    final keys = await list();
    final i = keys.indexWhere((k) => k.id == key.id);
    if (i >= 0) {
      keys[i] = key;
    } else {
      keys.add(key);
    }
    await _save(keys);
  }

  Future<void> remove(String id) async {
    final keys = await list()
      ..removeWhere((k) => k.id == id);
    await _save(keys);
  }
}
