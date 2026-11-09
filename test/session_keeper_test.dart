// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/ssh/session_keeper.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const name = 'test/sessions';
  late List<MethodCall> calls;
  late SessionKeeper keeper;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(name), (call) async {
          calls.add(call);
          return call.method == 'notificationsAllowed' ? false : null;
        });
    keeper = SessionKeeper(channel: const MethodChannel(name));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(name), null);
  });

  List<int> counts() => [
    for (final c in calls.where((c) => c.method == 'update'))
      (c.arguments as Map)['count'] as int,
  ];

  test('the count follows the sessions that open and close', () async {
    final a = Object();
    final b = Object();
    await keeper.opened(a, () {});
    await keeper.opened(b, () {});
    await keeper.closed(a);
    await keeper.closed(b);
    expect(counts(), [1, 2, 1, 0]);
    expect(keeper.count, 0);
  });

  test('closing something that was never opened pushes nothing', () async {
    await keeper.closed(Object());
    expect(calls, isEmpty);
  });

  test('closing twice counts once', () async {
    final a = Object();
    await keeper.opened(a, () {});
    await keeper.closed(a);
    await keeper.closed(a);
    expect(counts(), [1, 0]);
  });

  test('only the count is sent: no names, no text', () async {
    await keeper.opened(Object(), () {});
    final args = calls.single.arguments as Map;
    expect(args.keys, ['count']);
  });

  test(
    'switched off: the native side hears 0, sessions stay counted',
    () async {
      await keeper.opened(Object(), () {});
      await keeper.setEnabled(false);
      expect(counts(), [1, 0]);
      expect(keeper.count, 1);
      await keeper.opened(Object(), () {});
      expect(counts().last, 0); // still off
      await keeper.setEnabled(true);
      expect(counts().last, 2);
    },
  );

  test('Disconnect all closes every session, locked or not', () async {
    var closed = 0;
    final a = Object();
    final b = Object();
    await keeper.opened(a, () {
      closed++;
      keeper.closed(a);
    });
    await keeper.opened(b, () {
      closed++;
      keeper.closed(b);
    });
    final data = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('disconnectAll'),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(name, data, (_) {});
    expect(closed, 2);
    expect(keeper.count, 0);
    expect(counts().last, 0);
  });

  test('notification permission questions go to the native side', () async {
    expect(await keeper.notificationsAllowed(), isFalse);
    await keeper.requestNotifications();
    expect(
      calls.map((c) => c.method),
      containsAll(['notificationsAllowed', 'requestNotifications']),
    );
  });

  test('without a native side everything still works', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(name), null);
    await keeper.opened(Object(), () {});
    expect(await keeper.notificationsAllowed(), isTrue);
    expect(keeper.count, 1);
  });

  group('settings', () {
    test('keep-alive is on by default and the choice is kept', () async {
      final s = TerminalSettings(MemorySecureStore());
      expect(await s.loadKeepSessions(), isTrue);
      await s.saveKeepSessions(false);
      expect(await s.loadKeepSessions(), isFalse);
      await s.saveKeepSessions(true);
      expect(await s.loadKeepSessions(), isTrue);
    });

    test('the notification permission is explained only once', () async {
      final s = TerminalSettings(MemorySecureStore());
      expect(await s.loadNotificationAsked(), isFalse);
      await s.saveNotificationAsked();
      expect(await s.loadNotificationAsked(), isTrue);
    });
  });
}
