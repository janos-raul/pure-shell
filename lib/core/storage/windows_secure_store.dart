// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'secure_store.dart';

/// Windows Data Protection API, current user (runner: dpapi_channel.cpp).
abstract class Dpapi {
  Future<Uint8List> protect(Uint8List data);
  Future<Uint8List> unprotect(Uint8List data);
}

class PlatformDpapi implements Dpapi {
  const PlatformDpapi();

  static const _channel = MethodChannel('eu.pureshell.app/dpapi');

  @override
  Future<Uint8List> protect(Uint8List data) async =>
      (await _channel.invokeMethod<Uint8List>('protect', data))!;

  @override
  Future<Uint8List> unprotect(Uint8List data) async =>
      (await _channel.invokeMethod<Uint8List>('unprotect', data))!;
}

/// [SecureStore] for Windows: one JSON map, DPAPI-protected for the Windows
/// user, in `%LOCALAPPDATA%\Pure-Shell\store.dat` (Local, so it never roams
/// to other machines with a roaming profile).
///
/// The same format flutter_secure_storage_windows 4.x uses (DPAPI over a
/// JSON object, no extra entropy), so the spike's Roaming file can be read
/// and moved over once ([migrateFrom]).
class WindowsSecureStore implements SecureStore {
  WindowsSecureStore(this.directory, {this.dpapi = const PlatformDpapi()});

  final Directory directory;
  final Dpapi dpapi;
  Map<String, String>? _cache;
  Future<void> _queue = Future.value();

  static const fileName = 'store.dat';

  File get file => File('${directory.path}${Platform.pathSeparator}$fileName');

  /// The store the app uses, after moving any data the Roaming store of the
  /// first Windows builds still has.
  static Future<WindowsSecureStore> open() async {
    final env = Platform.environment;
    final store = WindowsSecureStore(
      Directory('${env['LOCALAPPDATA']}\\Pure-Shell'),
    );
    final roaming = env['APPDATA'];
    if (roaming != null) {
      // flutter_secure_storage: %APPDATA%\<CompanyName>\<ProductName> of the
      // old version resource.
      await store.migrateFrom(
        File('$roaming\\eu.pureshell\\pureshell\\flutter_secure_storage.dat'),
      );
    }
    return store;
  }

  /// Runs [op] after every earlier operation (reads see earlier writes,
  /// writes never interleave).
  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Map<String, String>> _decode(File f) async {
    final plain = await dpapi.unprotect(await f.readAsBytes());
    final map = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return {
      for (final e in map.entries)
        if (e.value is String) e.key: e.value as String,
    };
  }

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    _cache = await file.exists() ? await _decode(file) : <String, String>{};
    return _cache!;
  }

  Future<void> _save(Map<String, String> data) async {
    final protected = await dpapi.protect(utf8.encode(jsonEncode(data)));
    await directory.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(protected, flush: true);
    await tmp.rename(file.path); // replaces: never a half-written store
  }

  @override
  Future<String?> read(String key) => _serial(() async => (await _load())[key]);

  @override
  Future<void> write(String key, String value) => _serial(() async {
    final data = await _load();
    data[key] = value;
    await _save(data);
  });

  @override
  Future<void> delete(String key) => _serial(() async {
    final data = await _load();
    if (data.remove(key) != null) await _save(data);
  });

  /// Moves the entries of [legacy] (a flutter_secure_storage_windows file)
  /// into this store, once: entries already here win, then [legacy] and its
  /// folders, if left empty, are removed. A legacy file that cannot be read
  /// is left where it is.
  Future<void> migrateFrom(File legacy) => _serial(() async {
    if (!await legacy.exists()) return;
    final Map<String, String> old;
    try {
      old = await _decode(legacy);
    } catch (_) {
      return; // not ours to delete if we cannot read it
    }
    final data = await _load();
    final merged = {...old, ...data};
    if (merged.length != data.length) {
      await _save(merged);
      _cache = merged;
    }
    await legacy.delete();
    // The product and company folders, only if nothing else is in them.
    for (var dir = legacy.parent, i = 0; i < 2; dir = dir.parent, i++) {
      try {
        await dir.delete(); // non-recursive: fails when not empty
      } on FileSystemException {
        break;
      }
    }
  });
}
