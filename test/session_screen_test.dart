// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';

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
import 'package:pureshell/core/ssh/session_keeper.dart';
import 'package:pureshell/ui/terminal/direct_input.dart';
import 'package:pureshell/ui/terminal/terminal_screen.dart';

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

  late List<MethodCall> sessionCalls;
  late _Connection conn;
  late AppLockController lock;
  late MemorySecureStore store;
  var notificationsAllowed = true;

  List<int> counts() => [
    for (final c in sessionCalls.where((c) => c.method == 'update'))
      (c.arguments as Map)['count'] as int,
  ];

  Future<void> pumpScreen(WidgetTester t) async {
    PromptTracker.active.value = 0;
    final messenger = t.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(DirectInput.channelName),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(SessionKeeper.channelName),
      (call) async {
        sessionCalls.add(call);
        if (call.method == 'notificationsAllowed') return notificationsAllowed;
        if (call.method == 'requestNotifications') return true;
        return null;
      },
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel(DirectInput.channelName),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel(SessionKeeper.channelName),
        null,
      );
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

  setUp(() async {
    sessionCalls = [];
    store = MemorySecureStore();
    notificationsAllowed = true;
    await SessionKeeper.instance.setEnabled(true);
  });

  Future<void> disconnectAllFromNotification(WidgetTester t) async {
    final data = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('disconnectAll'),
    );
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      SessionKeeper.channelName,
      data,
      (_) {},
    );
    await t.pumpAndSettle();
  }

  testWidgets('a connected session is counted, an ended one is not', (t) async {
    await pumpScreen(t);
    expect(counts(), [1]);
    conn.fake!.doneC.complete();
    await t.pumpAndSettle();
    expect(counts(), [1, 0]);
  });

  testWidgets('leaving the screen stops counting', (t) async {
    await pumpScreen(t);
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(counts(), [1, 0]);
  });

  testWidgets('Disconnect all ends the session, even with the app locked', (
    t,
  ) async {
    await pumpScreen(t);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    await disconnectAllFromNotification(t);
    expect(counts().last, 0);
    expect(SessionKeeper.instance.count, 0);
    // (A paused app draws no frames: look at the banner once it is back.)
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('Disconnected from the notification.'), findsOneWidget);
  });

  testWidgets('the notification is explained once, after the first connect', (
    t,
  ) async {
    notificationsAllowed = false;
    await pumpScreen(t);
    expect(find.text('Keep sessions alive'), findsOneWidget);
    expect(
      find.textContaining('never shows hostnames, usernames or terminal'),
      findsOneWidget,
    );
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(sessionCalls.map((c) => c.method), contains('requestNotifications'));
    expect(await TerminalSettings(store).loadNotificationAsked(), isTrue);

    // Same store, next connect: not asked again.
    sessionCalls.clear();
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    conn = _Connection(store);
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
    expect(find.text('Keep sessions alive'), findsNothing);
    expect(
      sessionCalls.map((c) => c.method),
      isNot(contains('requestNotifications')),
    );
  });

  testWidgets('"Not now" never blocks and asks nothing', (t) async {
    notificationsAllowed = false;
    await pumpScreen(t);
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(
      sessionCalls.map((c) => c.method),
      isNot(contains('requestNotifications')),
    );
    expect(counts(), [1]); // still counted: the service runs regardless
  });

  testWidgets('keep-alive switched off: no explanation', (t) async {
    notificationsAllowed = false;
    // No mock native side yet: let the unhandled call finish in real time.
    await t.runAsync(() => SessionKeeper.instance.setEnabled(false));
    await pumpScreen(t);
    expect(find.text('Keep sessions alive'), findsNothing);
    expect(counts().last, 0); // the native side is told 0
  });
}
