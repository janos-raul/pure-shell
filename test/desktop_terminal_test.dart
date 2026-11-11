// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

// The terminal screen as the Windows build runs it (target platform
// overridden to Windows).

import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/ssh/ssh_connection.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/terminal/terminal_screen.dart';

const _host = Host(id: '1', label: 'Test', hostname: 'h', username: 'u');

class _FakeSession implements SSHSession {
  final stdinData = StreamController<Uint8List>();
  final out = StreamController<Uint8List>();
  final sent = <int>[];
  _FakeSession() {
    stdinData.stream.listen(sent.addAll);
  }

  @override
  StreamSink<Uint8List> get stdin => stdinData.sink;
  @override
  Stream<Uint8List> get stdout => out.stream;
  @override
  Stream<Uint8List> get stderr => const Stream.empty();
  @override
  Future<void> get done => Completer<void>().future;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Connection extends SshConnection {
  _Connection(MemorySecureStore store)
    : super(
        host: _host,
        knownHosts: KnownHostsStore(store),
        onTrustPrompt: (key, closed) async => true,
      );

  _FakeSession? fake;
  final resizes = <(int, int)>[];

  @override
  SSHSession? get session => fake;
  @override
  Future<SSHSession> openShell(int columns, int rows) async =>
      fake = _FakeSession();
  @override
  void resize(int columns, int rows) => resizes.add((columns, rows));
  @override
  void close() {}
}

final windows = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  late MemorySecureStore store;
  late _Connection conn;
  String? clipboard;

  Future<void> pumpScreen(WidgetTester t) async {
    store = MemorySecureStore();
    conn = _Connection(store);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        home: TerminalScreen(
          host: _host,
          connection: conn,
          settings: TerminalSettings(store),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  String sent() => String.fromCharCodes(conn.fake!.sent);

  Future<void> chord(
    WidgetTester t,
    List<LogicalKeyboardKey> mods,
    LogicalKeyboardKey key,
  ) async {
    for (final m in mods) {
      await t.sendKeyDownEvent(m);
    }
    await t.sendKeyEvent(key);
    for (final m in mods.reversed) {
      await t.sendKeyUpEvent(m);
    }
    await t.pumpAndSettle();
  }

  testWidgets('Ctrl+A, Ctrl+E, Ctrl+V and Alt+b reach the shell', (t) async {
    await pumpScreen(t);
    await chord(t, [LogicalKeyboardKey.controlLeft], LogicalKeyboardKey.keyA);
    await chord(t, [LogicalKeyboardKey.controlLeft], LogicalKeyboardKey.keyE);
    await chord(t, [LogicalKeyboardKey.controlLeft], LogicalKeyboardKey.keyV);
    await chord(t, [LogicalKeyboardKey.altLeft], LogicalKeyboardKey.keyB);
    expect(sent(), '\x01\x05\x16\x1bb');
  }, variant: windows);

  testWidgets('Ctrl+Shift+V pastes through the cleaned, guarded path', (
    t,
  ) async {
    await pumpScreen(t);
    clipboard = 'echo one\x1b[31m\necho two';
    await chord(t, [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.keyV);
    // Not bracketed: the same multi-line warning as on Android.
    expect(find.text('Paste 2 lines?'), findsOneWidget);
    await t.tap(find.text('Paste'));
    await t.pumpAndSettle();
    // Escape removed, line break -> \r, nothing else sent.
    expect(sent(), 'echo one[31m\recho two');
  }, variant: windows);

  testWidgets('Ctrl+Shift+C copies the selection', (t) async {
    await pumpScreen(t);
    clipboard = null;
    await chord(t, [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.keyC);
    // Nothing selected: nothing copied, and nothing went to the shell.
    expect(clipboard, isNull);
    expect(sent(), isEmpty);
  }, variant: windows);

  testWidgets('right-click menu: Copy only with a selection, then copies', (
    t,
  ) async {
    await pumpScreen(t);
    conn.fake!.out.add(utf8.encode('hello world'));
    await t.pumpAndSettle();
    final term = find.byType(TerminalScreen);

    await t.tapAt(t.getCenter(term), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Clear selection'), findsNothing);

    await t.tap(find.text('Select all'));
    await t.pumpAndSettle();
    await t.tapAt(t.getCenter(term), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    expect(find.text('Clear selection'), findsOneWidget);
    await t.tap(find.text('Copy'));
    await t.pumpAndSettle();
    expect(clipboard, contains('hello world'));
    expect(sent(), isEmpty);
  }, variant: windows);

  testWidgets('right-click Paste uses the cleaned paste path', (t) async {
    await pumpScreen(t);
    clipboard = 'ls\x07 -l';
    await t.tapAt(
      t.getCenter(find.byType(TerminalScreen)),
      buttons: kSecondaryButton,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Paste'));
    await t.pumpAndSettle();
    expect(sent(), 'ls -l'); // BEL removed, single line: no warning
  }, variant: windows);

  testWidgets(
    'Ctrl+= / Ctrl+- / Ctrl+0 zoom, are saved, never reach the shell',
    (t) async {
      await pumpScreen(t);
      final ctrl = [LogicalKeyboardKey.controlLeft];
      String? saved() => store.data[TerminalSettings.fontSizeKey];
      expect(TerminalSettings.initialFontSize, 14);
      await chord(t, ctrl, LogicalKeyboardKey.equal);
      expect(saved(), '15.0');
      await chord(t, ctrl, LogicalKeyboardKey.minus);
      await chord(t, ctrl, LogicalKeyboardKey.minus);
      expect(saved(), '13.0');
      await chord(t, ctrl, LogicalKeyboardKey.digit0);
      expect(saved(), '14.0');
      expect(sent(), isEmpty);
    },
    variant: windows,
  );
}
