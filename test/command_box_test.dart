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
import 'package:pureshell/ui/terminal/command_box.dart';
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

  late List<MethodCall> native;
  late _Connection conn;
  late AppLockController lock;

  Future<void> pumpScreen(WidgetTester t) async {
    PromptTracker.active.value = 0;
    final store = MemorySecureStore();
    native = [];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(DirectInput.channelName),
      (call) async {
        native.add(call);
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(DirectInput.channelName),
        null,
      ),
    );
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

  Future<void> typeNative(WidgetTester t, String text) async {
    final data = const StandardMethodCodec().encodeMethodCall(
      MethodCall('event', {'type': 'commit', 'text': text}),
    );
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      DirectInput.channelName,
      data,
      (_) {},
    );
    await t.pump();
  }

  String serverGot() => utf8.decode(conn.fake!.sent);
  final field = find.byKey(const ValueKey('command-box-field'));
  Terminal terminalOf(WidgetTester t) =>
      t.widget<TerminalView>(find.byType(TerminalView)).terminal;

  Future<void> openBox(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.edit_note));
    await t.pumpAndSettle();
  }

  group('command-line box', () {
    testWidgets('the field asks the keyboard for incognito, not for less', (
      t,
    ) async {
      await pumpScreen(t);
      await openBox(t);
      final f = t.widget<TextField>(field);
      expect(f.enableIMEPersonalizedLearning, isFalse);
      expect(f.autocorrect, isFalse);
      expect(f.textCapitalization, TextCapitalization.none);
      expect(f.enableSuggestions, isTrue);
      expect(f.minLines, 1);
      expect(f.maxLines, 3);
    });

    testWidgets('focus moves to the box; the native view is let go and drops '
        'input while it is open', (t) async {
      await pumpScreen(t);
      expect(native.map((c) => c.method), contains('attach'));
      native.clear();
      await openBox(t);
      expect(field, findsOneWidget);
      final detach = native.where((c) => c.method == 'detach').toList();
      expect(detach, isNotEmpty);
      // The keyboard is not hidden on the way to the box's field.
      expect((detach.last.arguments as Map)['hide'], isFalse);
      expect(native.map((c) => c.method), isNot(contains('attach')));
      expect(
        FocusManager.instance.primaryFocus,
        t.widget<TextField>(field).focusNode,
      );

      await typeNative(t, 'SECRET'); // still arrives from the native side
      expect(serverGot(), '');

      // Closing hands the keyboard back to the native view.
      native.clear();
      await t.tap(find.text('Esc'));
      await t.pumpAndSettle();
      expect(field, findsNothing);
      expect(native.map((c) => c.method), contains('attach'));
      await typeNative(t, 'x');
      expect(serverGot(), 'x');
    });

    testWidgets('send: text + Enter, field cleared, box closed', (t) async {
      await pumpScreen(t);
      await openBox(t);
      await t.enterText(field, 'ls -l');
      await t.tap(find.byIcon(Icons.send));
      await t.pumpAndSettle();
      expect(serverGot(), 'ls -l\r');
      expect(field, findsNothing);
      await openBox(t); // reopened: empty, nothing kept
      expect(t.widget<TextField>(field).controller!.text, '');
    });

    testWidgets('keep-open toggle: the box stays and is cleared', (t) async {
      await pumpScreen(t);
      await openBox(t);
      await t.tap(find.byIcon(Icons.push_pin_outlined));
      await t.pump();
      await t.enterText(field, 'one');
      await t.tap(find.byIcon(Icons.send));
      await t.pumpAndSettle();
      expect(field, findsOneWidget);
      expect(t.widget<TextField>(field).controller!.text, '');
      await t.enterText(field, 'two');
      await t.tap(find.byIcon(Icons.send));
      await t.pumpAndSettle();
      expect(serverGot(), 'one\rtwo\r');
    });

    testWidgets('a typed Enter at the end sends', (t) async {
      await pumpScreen(t);
      await openBox(t);
      await t.enterText(field, 'pwd');
      await t.enterText(field, 'pwd\n');
      await t.pumpAndSettle();
      expect(serverGot(), 'pwd\r');
      expect(field, findsNothing);
    });

    testWidgets('line breaks go through the paste path, no Enter added', (
      t,
    ) async {
      await pumpScreen(t);
      // The program asked for bracketed paste.
      terminalOf(t).write('\x1b[?2004h');
      await openBox(t);
      await t.enterText(field, 'echo a\necho b');
      await t.tap(find.byIcon(Icons.send));
      await t.pumpAndSettle();
      expect(serverGot(), '\x1b[200~echo a\recho b\x1b[201~');
    });

    testWidgets('line breaks without bracketed paste: still no final Enter', (
      t,
    ) async {
      await pumpScreen(t);
      await openBox(t);
      await t.enterText(field, 'a\nb');
      await t.tap(find.byIcon(Icons.send));
      await t.pumpAndSettle();
      expect(serverGot(), 'a\rb');
    });

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
    ]) {
      testWidgets('the box closes and its text is cleared on $state', (
        t,
      ) async {
        await pumpScreen(t);
        await openBox(t);
        await t.enterText(field, 'hunter2');
        t.binding.handleAppLifecycleStateChanged(state);
        await t.pump();
        expect(field, findsNothing);
        expect(find.text('hunter2'), findsNothing);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        await openBox(t);
        expect(t.widget<TextField>(field).controller!.text, '');
        expect(serverGot(), '');
      });
    }

    testWidgets('the box closes and clears when the app lock covers', (
      t,
    ) async {
      PromptTracker.active.value = 0;
      final store = MemorySecureStore();
      native = [];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(DirectInput.channelName),
        (call) async => null,
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel(DirectInput.channelName),
          null,
        ),
      );
      conn = _Connection(store);
      lock = AppLockController(
        FakeKeystore()..secureLock = true,
        AppLockSettings(store),
      );
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
      await openBox(t);
      await t.enterText(field, 'secret');
      await lock.handleLifecycle(AppLifecycleState.inactive);
      await t.pump();
      expect(lock.hidden, isTrue);
      expect(field, findsNothing);
      await lock.handleLifecycle(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      await openBox(t);
      expect(t.widget<TextField>(field).controller!.text, '');
    });

    testWidgets('no extra key reaches the session while the box is open', (
      t,
    ) async {
      await pumpScreen(t);
      await openBox(t);
      await t.enterText(field, 'abc');
      for (final label in ['←', '↑', '↓', '→', '|', '~', '/', 'Tab', 'Ctrl']) {
        await t.tap(find.text(label));
        await t.pump();
      }
      expect(serverGot(), '');
      // Arrows moved the cursor and the character keys typed into the box.
      expect(t.widget<TextField>(field).controller!.text, contains('|~/'));
      // Esc closes the box and clears it.
      await t.tap(find.text('Esc'));
      await t.pumpAndSettle();
      expect(field, findsNothing);
      expect(serverGot(), '');
    });

    testWidgets('Tab and Ctrl are dimmed and disabled in the box', (t) async {
      await pumpScreen(t);
      await openBox(t);
      for (final label in ['Tab', 'Ctrl']) {
        final inkWell = find.ancestor(
          of: find.text(label),
          matching: find.byType(InkWell),
        );
        expect(t.widget<InkWell>(inkWell).onTap, isNull);
        final opacity = find.ancestor(
          of: find.text(label),
          matching: find.byType(Opacity),
        );
        expect(t.widget<Opacity>(opacity).opacity, lessThan(1));
      }
    });

    testWidgets('sticky Ctrl is released when the box opens', (t) async {
      await pumpScreen(t);
      await t.tap(find.text('Ctrl'));
      await t.pump();
      await openBox(t);
      await t.tap(find.text('Esc'));
      await t.pumpAndSettle();
      await typeNative(t, 'c');
      expect(serverGot(), 'c'); // not Ctrl+C (\x03)
    });

    testWidgets('the box cannot open without a live session', (t) async {
      await pumpScreen(t);
      conn.fake!.doneC.complete();
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.edit_note));
      await t.pumpAndSettle();
      expect(field, findsNothing);
    });
  });

  group('moveCaret', () {
    test('left and right stay inside the text', () {
      expect(moveCaret('abc', 0, dx: -1), 0);
      expect(moveCaret('abc', 3, dx: 1), 3);
      expect(moveCaret('abc', 1, dx: 1), 2);
    });

    test('up and down move by line, keeping the column', () {
      const t = 'abcd\nef\nghij';
      expect(moveCaret(t, 11, dy: -1), 7); // col 3 -> end of short line
      expect(moveCaret(t, 7, dy: -1), 2); // col 2 of "ef" -> col 2 of line 1
      expect(moveCaret(t, 2, dy: 1), 7);
      expect(moveCaret(t, 2, dy: -1), 0); // first line: to the start
      expect(moveCaret(t, 11, dy: 1), t.length); // last line: to the end
    });
  });
}
