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

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/keys/keystore_api.dart';
import 'package:pureshell/core/lock/app_lock_controller.dart';
import 'package:pureshell/core/lock/app_lock_settings.dart';
import 'package:pureshell/core/ssh/ssh_connection.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/lock/app_lock_gate.dart';
import 'package:pureshell/ui/terminal/terminal_clipboard.dart';
import 'package:pureshell/ui/terminal/direct_input.dart';
import 'package:pureshell/ui/terminal/terminal_screen.dart';
import 'package:xterm/xterm.dart';

import 'fake_keystore.dart';

const _host = Host(
  id: '1',
  label: 'Test',
  hostname: 'example.com',
  username: 'u',
);

class _FakeSession implements SSHSession {
  final stdinData = StreamController<Uint8List>();
  final doneC = Completer<void>();
  final sent = <int>[];

  _FakeSession() {
    stdinData.stream.listen(sent.addAll);
  }

  @override
  StreamSink<Uint8List> get stdin => stdinData.sink;
  @override
  Stream<Uint8List> get stdout => const Stream.empty();
  @override
  Stream<Uint8List> get stderr => const Stream.empty();
  @override
  Future<void> get done => doneC.future;

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

  @override
  SSHSession? get session => fake;

  @override
  Future<SSHSession> openShell(int columns, int rows) async =>
      fake = _FakeSession();

  @override
  void resize(int columns, int rows) {}

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Connection conn;
  late AppLockController lock;
  late List<String> nativeCopies; // text sent to the sensitive-copy channel
  late int clipboardReads;
  String clip = '';

  Future<void> pumpScreen(WidgetTester t) async {
    PromptTracker.active.value = 0;
    final store = MemorySecureStore();
    nativeCopies = [];
    clipboardReads = 0;
    final messenger = t.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(DirectInput.channelName),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(TerminalClipboard.channelName),
      (call) async {
        nativeCopies.add((call.arguments as Map)['text'] as String);
        return null;
      },
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        clipboardReads++;
        return <String, dynamic>{'text': clip};
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel(DirectInput.channelName),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel(TerminalClipboard.channelName),
        null,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    conn = _Connection(store);
    lock = AppLockController(FakeKeystore(), AppLockSettings(store));
    await lock.init();
    if (lock.locked) await lock.unlock();
    await t.pumpWidget(
      MaterialApp(
        home: AppLockScope(
          controller: lock,
          child: TerminalScreen(
            host: _host,
            connection: conn,
            settings: TerminalSettings(store),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  String serverGot() => utf8.decode(conn.fake!.sent);
  TerminalView viewOf(WidgetTester t) =>
      t.widget<TerminalView>(find.byType(TerminalView));
  Terminal terminalOf(WidgetTester t) => viewOf(t).terminal;
  final pasteKey = find.byIcon(Icons.content_paste);
  final field = find.byKey(const ValueKey('command-box-field'));

  Future<void> longPress(WidgetTester t, {VoidCallback? during}) async {
    final g = await t.startGesture(const Offset(40, 100));
    await t.pump(const Duration(milliseconds: 300));
    during?.call();
    await t.pump(const Duration(milliseconds: 500));
    await g.up();
    await t.pumpAndSettle();
  }

  PopupMenuItem<String> item(WidgetTester t, String label) =>
      t.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );

  group('sanitizePaste', () {
    test('line breaks become Enter, Escape and control keys are dropped', () {
      expect(sanitizePaste('a\r\nb\nc\rd'), 'a\rb\rc\rd');
      expect(sanitizePaste('x\x1b[201~rm -rf ~'), 'x[201~rm -rf ~');
      expect(sanitizePaste('a\x03b\x00c\x7fd\te'), 'abcd\te');
      expect(sanitizePaste('héllo ✓'), 'héllo ✓');
    });
  });

  group('paste', () {
    testWidgets('the clipboard is read only when Paste is tapped', (t) async {
      clip = 'ls';
      await pumpScreen(t);
      expect(clipboardReads, 0);
      await t.tap(pasteKey);
      await t.pumpAndSettle();
      expect(clipboardReads, 1);
      expect(serverGot(), 'ls');
    });

    testWidgets('bracketed paste: multi-line text is wrapped, never run', (
      t,
    ) async {
      clip = 'echo a\necho b\n';
      await pumpScreen(t);
      terminalOf(t).write('\x1b[?2004h');
      await t.tap(pasteKey);
      await t.pumpAndSettle();
      expect(serverGot(), '\x1b[200~echo a\recho b\r\x1b[201~');
    });

    testWidgets('an Escape in the clipboard cannot end the paste early', (
      t,
    ) async {
      clip = 'x\x1b[201~\nrm -rf ~';
      await pumpScreen(t);
      terminalOf(t).write('\x1b[?2004h');
      await t.tap(pasteKey);
      await t.pumpAndSettle();
      final got = serverGot();
      expect(got.startsWith('\x1b[200~'), isTrue);
      expect(got.endsWith('\x1b[201~'), isTrue);
      expect('\x1b'.allMatches(got).length, 2); // only our two markers
    });

    testWidgets('no bracketed paste, several lines: asks first', (t) async {
      clip = 'one\ntwo';
      await pumpScreen(t);
      await t.tap(pasteKey);
      await t.pumpAndSettle();
      expect(find.text('Paste 2 lines?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(serverGot(), '');

      await t.tap(pasteKey);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Paste'));
      await t.pumpAndSettle();
      expect(serverGot(), 'one\rtwo');
    });

    testWidgets('no bracketed paste, one line: no question', (t) async {
      clip = 'single line';
      await pumpScreen(t);
      await t.tap(pasteKey);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(serverGot(), 'single line');
    });

    testWidgets('with the box open, Paste goes into the box only', (t) async {
      clip = 'pasted';
      await pumpScreen(t);
      await t.tap(find.byIcon(Icons.edit_note));
      await t.pumpAndSettle();
      await t.tap(pasteKey);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).controller!.text, 'pasted');
      expect(serverGot(), '');
    });

    testWidgets('locked or backgrounded: Paste does nothing, no read', (
      t,
    ) async {
      clip = 'secret';
      await pumpScreen(t);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      await t.tap(pasteKey);
      await t.pumpAndSettle();
      expect(clipboardReads, 0);
      expect(serverGot(), '');
    });
  });

  group('long-press menu', () {
    testWidgets('Paste always; Copy and Select all with a selection', (
      t,
    ) async {
      clip = 'ls';
      await pumpScreen(t);
      terminalOf(t).write('hello world');
      await longPress(
        t,
        during: () {
          final b = terminalOf(t).buffer;
          viewOf(t).controller!
              .setSelection(b.createAnchor(0, 0), b.createAnchor(5, 0));
        },
      );
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
      expect(item(t, 'Paste').enabled, isTrue);

      await t.tap(find.text('Paste'));
      await t.pumpAndSettle();
      expect(serverGot(), 'ls');
    });

    testWidgets('without a selection only Paste is offered', (t) async {
      await pumpScreen(t);
      viewOf(t).controller!.clearSelection();
      // Press where xterm has nothing to select (far from any text).
      final g = await t.startGesture(const Offset(300, 400));
      await t.pump(const Duration(milliseconds: 100));
      viewOf(t).controller!.clearSelection();
      await t.pump(const Duration(milliseconds: 700));
      await g.up();
      await t.pumpAndSettle();
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Select all'), findsNothing);
    });

    testWidgets('Copy sends the selection to the sensitive-copy channel', (
      t,
    ) async {
      await pumpScreen(t);
      terminalOf(t).write('hello world');
      await longPress(
        t,
        during: () {
          final b = terminalOf(t).buffer;
          viewOf(t).controller!
              .setSelection(b.createAnchor(0, 0), b.createAnchor(5, 0));
        },
      );
      await t.tap(find.text('Copy'));
      await t.pumpAndSettle();
      expect(nativeCopies.single.trim(), 'hello');
      expect(serverGot(), '');
    });

    testWidgets('Select all selects the whole buffer', (t) async {
      await pumpScreen(t);
      terminalOf(t).write('hello world');
      await longPress(
        t,
        during: () {
          final b = terminalOf(t).buffer;
          viewOf(t).controller!
              .setSelection(b.createAnchor(0, 0), b.createAnchor(2, 0));
        },
      );
      await t.tap(find.text('Select all'));
      await t.pumpAndSettle();
      final text = terminalOf(t).buffer
          .getText(viewOf(t).controller!.selection);
      expect(text, contains('hello world'));
    });

    testWidgets('locked: the menu items are disabled and do nothing', (
      t,
    ) async {
      clip = 'secret';
      await pumpScreen(t);
      terminalOf(t).write('hello world');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      await longPress(
        t,
        during: () {
          final b = terminalOf(t).buffer;
          viewOf(t).controller!
              .setSelection(b.createAnchor(0, 0), b.createAnchor(5, 0));
        },
      );
      expect(item(t, 'Paste').enabled, isFalse);
      expect(item(t, 'Copy').enabled, isFalse);
      expect(item(t, 'Select all').enabled, isFalse);
      await t.tap(find.text('Paste'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(clipboardReads, 0);
      expect(nativeCopies, isEmpty);
      expect(serverGot(), '');
    });

    testWidgets('the app locked while the menu was open: actions do nothing', (
      t,
    ) async {
      clip = 'secret';
      await pumpScreen(t);
      terminalOf(t).write('hello world');
      final g = await t.startGesture(const Offset(40, 100));
      await t.pump(const Duration(milliseconds: 300));
      final b = terminalOf(t).buffer;
      viewOf(t).controller!
          .setSelection(b.createAnchor(0, 0), b.createAnchor(5, 0));
      await t.pump(const Duration(milliseconds: 500));
      await g.up();
      await t.pumpAndSettle();
      expect(item(t, 'Copy').enabled, isTrue);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      await t.tap(find.text('Copy'));
      await t.pumpAndSettle();
      expect(nativeCopies, isEmpty);
    });
  });
}
