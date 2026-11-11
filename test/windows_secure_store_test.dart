// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/storage/windows_secure_store.dart';

/// Stand-in for DPAPI: reversible, and never the plain text.
class _FakeDpapi implements Dpapi {
  static Uint8List _x(Uint8List d) =>
      Uint8List.fromList([for (final b in d) b ^ 0x5a]);
  @override
  Future<Uint8List> protect(Uint8List data) async => _x(data);
  @override
  Future<Uint8List> unprotect(Uint8List data) async => _x(data);
}

void main() {
  late Directory tmp;
  late Directory local;
  final dpapi = _FakeDpapi();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pureshell_store_');
    local = Directory('${tmp.path}/Local/Pure-Shell');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<File> legacyFile(Map<String, String> data) async {
    final f = File('${tmp.path}/Roaming/eu.pureshell/pureshell/legacy.dat');
    await f.create(recursive: true);
    await f.writeAsBytes(await dpapi.protect(utf8.encode(jsonEncode(data))));
    return f;
  }

  test('round trip, persisted protected, survives a new instance', () async {
    final s = WindowsSecureStore(local, dpapi: dpapi);
    await s.write('a', '1');
    await s.write('b', 'secret-value');
    await s.delete('a');
    expect(await s.read('b'), 'secret-value');
    expect(await s.read('a'), isNull);
    final raw = await s.file.readAsBytes();
    expect(utf8.decode(raw, allowMalformed: true), isNot(contains('secret')));
    final again = WindowsSecureStore(local, dpapi: dpapi);
    expect(await again.read('b'), 'secret-value');
    expect(File('${s.file.path}.tmp').existsSync(), isFalse);
  });

  test('concurrent writes all land', () async {
    final s = WindowsSecureStore(local, dpapi: dpapi);
    await Future.wait([for (var i = 0; i < 20; i++) s.write('k$i', '$i')]);
    final again = WindowsSecureStore(local, dpapi: dpapi);
    for (var i = 0; i < 20; i++) {
      expect(await again.read('k$i'), '$i');
    }
  });

  test('migrates the Roaming store once, then removes it', () async {
    final legacy = await legacyFile({'hosts': '[1]', 'x': 'old'});
    final s = WindowsSecureStore(local, dpapi: dpapi);
    await s.write('x', 'new'); // already here: wins over the old value
    await s.migrateFrom(legacy);
    expect(await s.read('hosts'), '[1]');
    expect(await s.read('x'), 'new');
    expect(legacy.existsSync(), isFalse);
    // Empty product and company folders are gone too.
    expect(Directory('${tmp.path}/Roaming/eu.pureshell').existsSync(), isFalse);
    expect(Directory('${tmp.path}/Roaming').existsSync(), isTrue);
    // A second run has nothing to do.
    await s.migrateFrom(legacy);
    expect(await WindowsSecureStore(local, dpapi: dpapi).read('hosts'), '[1]');
  });

  test('an unreadable legacy file is left alone', () async {
    final f = File('${tmp.path}/Roaming/eu.pureshell/pureshell/legacy.dat');
    await f.create(recursive: true);
    await f.writeAsBytes([1, 2, 3]); // not JSON after "decrypting"
    final s = WindowsSecureStore(local, dpapi: dpapi);
    await s.migrateFrom(f);
    expect(f.existsSync(), isTrue);
    expect(await s.read('anything'), isNull);
  });
}
