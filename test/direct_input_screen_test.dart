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
import 'package:pureshell/ui/terminal/direct_input.dart';
import 'package:pureshell/ui/terminal/terminal_screen.dart';

import 'fake_keystore.dart';

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
        host: const Host(
          id: '1',
          label: 'Test',
          hostname: 'example.com',
          username: 'u',
        ),
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

  late List<String> calls;
  late _Connection conn;
  late AppLockController lock;

  Future<void> pumpScreen(WidgetTester t, {required bool lockActive}) async {
    PromptTracker.active.value = 0;
    final store = MemorySecureStore();
    calls = [];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(DirectInput.channelName),
      (call) async {
        calls.add(call.method == 'detach' ? 'detach' : call.method);
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
    final keystore = FakeKeystore()..secureLock = lockActive;
    lock = AppLockController(keystore, AppLockSettings(store));
    await lock.init();
    if (lock.locked) await lock.unlock();
    await t.pumpWidget(
      MaterialApp(
        home: AppLockScope(
          controller: lock,
          child: TerminalScreen(
            host: const Host(
              id: '1',
              label: 'Test',
              hostname: 'example.com',
              username: 'u',
            ),
            connection: conn,
            settings: TerminalSettings(store),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  /// What the native view does when the user types: an event on the channel.
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

  testWidgets('with a live session the keyboard attaches and typing arrives', (
    t,
  ) async {
    await pumpScreen(t, lockActive: false);
    expect(calls, contains('attach'));
    await typeNative(t, 'ls');
    expect(serverGot(), 'ls');
  });

  testWidgets('the lock cover detaches the keyboard and drops input', (
    t,
  ) async {
    await pumpScreen(t, lockActive: true);
    await typeNative(t, 'a');
    expect(serverGot(), 'a');

    calls.clear();
    await lock.handleLifecycle(AppLifecycleState.inactive); // cover shown
    await t.pump();
    expect(lock.hidden, isTrue);
    expect(calls, contains('detach'));
    expect(calls, isNot(contains('attach')));

    await typeNative(t, 'SECRET'); // still arrives from the native side
    expect(serverGot(), 'a');

    calls.clear();
    await lock.handleLifecycle(AppLifecycleState.resumed);
    await t.pump();
    expect(calls, contains('attach'));
    await typeNative(t, 'b');
    expect(serverGot(), 'ab');
  });

  testWidgets('backgrounded (even with app lock off): detached, dropped', (
    t,
  ) async {
    await pumpScreen(t, lockActive: false);
    expect(lock.active, isFalse);

    calls.clear();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(calls, contains('detach'));
    await typeNative(t, 'SECRET');
    expect(serverGot(), '');

    calls.clear();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(calls, contains('attach'));
    await typeNative(t, 'x');
    expect(serverGot(), 'x');
  });

  testWidgets('when the session ends: detached, dropped', (t) async {
    await pumpScreen(t, lockActive: false);
    calls.clear();
    conn.fake!.doneC.complete();
    await t.pumpAndSettle();
    expect(calls, contains('detach'));
    await typeNative(t, 'SECRET');
    expect(serverGot(), '');
  });

  testWidgets('no session yet: the keyboard is not attached', (t) async {
    // A connection whose shell never opens.
    PromptTracker.active.value = 0;
    final store = MemorySecureStore();
    final recorded = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(DirectInput.channelName),
      (call) async {
        recorded.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(DirectInput.channelName),
        null,
      ),
    );
    final never = _NeverOpens(store);
    await t.pumpWidget(
      MaterialApp(
        home: TerminalScreen(
          host: const Host(
            id: '1',
            label: 'Test',
            hostname: 'example.com',
            username: 'u',
          ),
          connection: never,
          settings: TerminalSettings(store),
        ),
      ),
    );
    await t.pump();
    expect(recorded, isNot(contains('attach')));
  });
}

class _NeverOpens extends _Connection {
  _NeverOpens(super.store);

  @override
  Future<SSHSession> openShell(int columns, int rows) =>
      Completer<SSHSession>().future;
}
