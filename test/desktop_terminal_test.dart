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
import 'package:pureshell/core/lock/app_lock_controller.dart';
import 'package:pureshell/core/lock/app_lock_settings.dart';
import 'package:pureshell/ui/lock/app_lock_gate.dart';

import 'fake_keystore.dart';

import 'package:pureshell/ui/terminal/extra_keys.dart';
import 'package:pureshell/ui/terminal/terminal_clipboard.dart';
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

Widget _withLock(AppLockController? lock, Widget child) =>
    lock == null ? child : AppLockScope(controller: lock, child: child);

void main() {
  late MemorySecureStore store;
  late _Connection conn;
  String? clipboard;
  final sensitiveCopies = <String>[];

  Future<void> pumpScreen(
    WidgetTester t, {
    bool? showExtraKeys,
    AppLockController? lock,
  }) async {
    store = MemorySecureStore();
    if (showExtraKeys != null) {
      store.data[TerminalSettings.showExtraKeysKey] = '$showExtraKeys';
    }
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
    sensitiveCopies.clear();
    // The runner's clipboard channel (window_channels.cpp).
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(TerminalClipboard.channelName),
      (call) async {
        sensitiveCopies.add((call.arguments as Map)['text'] as String);
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(TerminalClipboard.channelName),
        null,
      ),
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        home: _withLock(
          lock,
          TerminalScreen(
            host: _host,
            connection: conn,
            settings: TerminalSettings(store),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  String sent() => utf8.decode(conn.fake!.sent);

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
    // Copied through the sensitive path, not the plain system clipboard.
    expect(sensitiveCopies.single, contains('hello world'));
    expect(clipboard, isNull);
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

  testWidgets('wide window: top bar with Disconnect, no extra keys row', (
    t,
  ) async {
    await pumpScreen(t); // the test surface (800 x 600) is landscape
    expect(find.byTooltip('Disconnect'), findsOneWidget);
    expect(find.byType(ExtraKeysRow), findsNothing);
  }, variant: windows);

  testWidgets('extra keys row when turned on', (t) async {
    await pumpScreen(t, showExtraKeys: true);
    expect(find.byType(ExtraKeysRow), findsOneWidget);
  }, variant: windows);

  testWidgets(
    'typed text (IME, emoji panel, remote desktop) reaches the shell',
    (t) async {
      await pumpScreen(t);
      // The text input connection is open as soon as the terminal has focus.
      expect(t.testTextInput.hasAnyClients, isTrue);
      t.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ls 😀',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await t.pumpAndSettle();
      expect(sent(), 'ls 😀');
    },
    variant: windows,
  );

  testWidgets('IME composition is shown, only the committed text is sent', (
    t,
  ) async {
    await pumpScreen(t);
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'にほ',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await t.pump();
    expect(find.text('にほ'), findsOneWidget);
    expect(sent(), isEmpty);
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '日本',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('にほ'), findsNothing);
    expect(sent(), '日本');
  }, variant: windows);

  testWidgets('a typed letter key is sent once', (t) async {
    await pumpScreen(t);
    await t.sendKeyEvent(LogicalKeyboardKey.keyW);
    await t.pumpAndSettle();
    expect(sent(), 'w');
  }, variant: windows);

  testWidgets('while locked no key or text reaches the server', (t) async {
    final lock = AppLockController(
      FakeKeystore(),
      AppLockSettings(MemorySecureStore()),
      desktop: true,
    );
    await lock.init();
    expect(lock.locked, isTrue);
    await pumpScreen(t, lock: lock);
    await chord(t, [LogicalKeyboardKey.controlLeft], LogicalKeyboardKey.keyA);
    await t.sendKeyEvent(LogicalKeyboardKey.keyW);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(t.testTextInput.hasAnyClients, isFalse);
    expect(sent(), isEmpty);
  }, variant: windows);
}
