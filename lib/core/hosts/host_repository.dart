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
import 'host.dart';
import 'known_hosts.dart';

/// Stores the host list as one JSON document in encrypted storage.
class HostRepository {
  HostRepository(this._store, {this.knownHosts});

  static const storageKey = 'hosts.v1';

  final SecureStore _store;
  final KnownHostsStore? knownHosts;

  Future<List<Host>> list() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => Host.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save(List<Host> hosts) => _store.write(
        storageKey,
        jsonEncode(hosts.map((h) => h.toJson()).toList()),
      );

  /// Adds the host, or replaces the one with the same id.
  Future<void> upsert(Host host) async {
    final hosts = await list();
    final i = hosts.indexWhere((h) => h.id == host.id);
    if (i >= 0) {
      hosts[i] = host;
    } else {
      hosts.add(host);
    }
    await _save(hosts);
  }

  /// Deletes the host and its trusted host key.
  Future<void> delete(Host host) async {
    final hosts = await list()..removeWhere((h) => h.id == host.id);
    await _save(hosts);
    await knownHosts?.remove(host.hostname, host.port);
  }
}
