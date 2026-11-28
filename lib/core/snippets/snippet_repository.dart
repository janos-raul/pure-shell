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
import 'snippet.dart';

/// Stores all snippets as one JSON document in encrypted storage, the same
/// way [HostRepository] stores hosts. The order in the list is the order shown.
class SnippetRepository {
  SnippetRepository(this._store);

  static const storageKey = 'snippets.v1';

  final SecureStore _store;

  Future<List<Snippet>> list() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List<dynamic>)
          Snippet.fromJson(e as Map<String, dynamic>),
      ];
    } on Object {
      // A damaged document must not break the session screen.
      return [];
    }
  }

  Future<void> _save(List<Snippet> all) =>
      _store.write(storageKey, jsonEncode([for (final s in all) s.toJson()]));

  /// The snippets of one scope, in their order: [hostId] null is the global
  /// list.
  Future<List<Snippet>> inScope(String? hostId) async => [
    for (final s in await list())
      if (s.hostId == hostId) s,
  ];

  /// What the session sheet shows: the host's own snippets first, then the
  /// global ones.
  Future<List<Snippet>> forHost(String hostId) async {
    final all = await list();
    return [
      for (final s in all)
        if (s.hostId == hostId) s,
      for (final s in all)
        if (s.hostId == null) s,
    ];
  }

  /// Adds the snippet at the end, or replaces the one with the same id (it
  /// keeps its place; moving it to another scope puts it at the end).
  Future<void> upsert(Snippet snippet) async {
    final all = await list();
    final i = all.indexWhere((s) => s.id == snippet.id);
    if (i >= 0 && all[i].hostId == snippet.hostId) {
      all[i] = snippet;
    } else {
      if (i >= 0) all.removeAt(i);
      all.add(snippet);
    }
    await _save(all);
  }

  Future<void> delete(Snippet snippet) async {
    final all = await list()
      ..removeWhere((s) => s.id == snippet.id);
    await _save(all);
  }

  /// Removes every snippet tied to [hostId] (the host was deleted).
  Future<void> deleteForHost(String hostId) async {
    final all = await list();
    final kept = [
      for (final s in all)
        if (s.hostId != hostId) s,
    ];
    if (kept.length != all.length) await _save(kept);
  }

  /// Moves one snippet inside its scope, like [ReorderableListView]: indexes
  /// are positions in the scope's own list, and [newIndex] is the position
  /// before the removal. Other scopes keep their order.
  Future<void> reorder(String? hostId, int oldIndex, int newIndex) async {
    final all = await list();
    final slots = [
      for (var i = 0; i < all.length; i++)
        if (all[i].hostId == hostId) i,
    ];
    if (oldIndex < 0 || oldIndex >= slots.length) return;
    final scoped = [for (final i in slots) all[i]];
    final moved = scoped.removeAt(oldIndex);
    if (newIndex > oldIndex) newIndex -= 1;
    scoped.insert(newIndex.clamp(0, scoped.length), moved);
    for (var k = 0; k < slots.length; k++) {
      all[slots[k]] = scoped[k];
    }
    await _save(all);
  }
}
