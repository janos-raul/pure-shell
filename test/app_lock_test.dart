// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/keys/keystore_api.dart';
import 'package:pureshell/core/lock/app_lock_controller.dart';
import 'package:pureshell/core/lock/app_lock_settings.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/ui/lock/app_lock_gate.dart';

import 'fake_keystore.dart';

/// FakeKeystore whose unlock prompt the test controls.
class LockKeystore extends FakeKeystore {
  var authenticateCalls = 0;
  bool cancelAuth = false;

  @override
  Future<void> authenticate({String title = '', String? subtitle}) async {
    authenticateCalls++;
    if (cancelAuth) {
      throw const KeystoreException(KeystoreErrorKind.cancelled);
    }
  }
}

void main() {
  late LockKeystore keystore;
  late MemorySecureStore store;
  var clock = DateTime(2026, 1, 1);
  AppLockController make() =>
      AppLockController(keystore, AppLockSettings(store), now: () => clock);

  setUp(() {
    keystore = LockKeystore();
    store = MemorySecureStore();
    clock = DateTime(2026, 1, 1);
    PromptTracker.active.value = 0;
  });

  group('when it locks', () {
    test('on by default: the app starts locked', () async {
      final c = make();
      await c.init();
      expect(c.enabled, isTrue);
      expect(c.timeout, LockTimeout.oneMinute);
      expect(c.locked, isTrue);
      expect(c.hidden, isTrue);
    });

    test('switched off: never locked, never covered', () async {
      final c = make();
      await c.init();
      await c.setEnabled(false);
      expect(c.locked, isFalse);
      await c.handleLifecycle(AppLifecycleState.paused);
      expect(c.hidden, isFalse);
    });

    test('a short absence does not lock, a long one does', () async {
      final c = make();
      await c.init();
      await c.unlock();
      expect(c.locked, isFalse);

      await c.handleLifecycle(AppLifecycleState.paused);
      clock = clock.add(const Duration(seconds: 30));
      await c.handleLifecycle(AppLifecycleState.resumed);
      expect(c.locked, isFalse);
      expect(c.hidden, isFalse);

      await c.handleLifecycle(AppLifecycleState.paused);
      clock = clock.add(const Duration(minutes: 2));
      await c.handleLifecycle(AppLifecycleState.resumed);
      expect(c.locked, isTrue);
    });

    test('every timeout choice is honoured', () async {
      for (final t in LockTimeout.values) {
        final c = make();
        await c.init();
        await c.setTimeout(t);
        await c.unlock();
        await c.handleLifecycle(AppLifecycleState.paused);
        clock = clock.add(
          t == LockTimeout.immediately
              ? Duration.zero
              : t.duration - const Duration(seconds: 1),
        );
        await c.handleLifecycle(AppLifecycleState.resumed);
        expect(
          c.locked,
          t == LockTimeout.immediately,
          reason: 'just under ${t.label}',
        );
        await c.unlock();
        await c.handleLifecycle(AppLifecycleState.paused);
        clock = clock.add(t.duration);
        await c.handleLifecycle(AppLifecycleState.resumed);
        expect(c.locked, isTrue, reason: 'at ${t.label}');
      }
    });

    test('the timeout setting is remembered', () async {
      final c = make();
      await c.init();
      await c.setTimeout(LockTimeout.fifteenMinutes);
      await c.setEnabled(false);
      final again = make();
      await again.init();
      expect(again.timeout, LockTimeout.fifteenMinutes);
      expect(again.enabled, isFalse);
    });
  });

  group('covering', () {
    test(
      'content is hidden the moment focus is lost, before any lock',
      () async {
        final c = make();
        await c.init();
        await c.unlock();
        expect(c.hidden, isFalse);
        await c.handleLifecycle(AppLifecycleState.inactive); // recents
        expect(c.hidden, isTrue);
        expect(c.locked, isFalse);
        await c.handleLifecycle(AppLifecycleState.resumed);
        expect(c.hidden, isFalse);
      },
    );

    test('a fingerprint prompt taking focus does not lock the app', () async {
      final c = make();
      await c.init();
      await c.setTimeout(LockTimeout.immediately);
      await c.unlock();
      PromptTracker.active.value = 1; // a key use is showing its prompt
      await c.handleLifecycle(AppLifecycleState.inactive);
      await c.handleLifecycle(AppLifecycleState.resumed);
      PromptTracker.active.value = 0;
      expect(c.locked, isFalse);
      expect(c.hidden, isFalse);
    });
  });

  group('unlocking', () {
    test('success unlocks', () async {
      final c = make();
      await c.init();
      expect(await c.unlock(), isTrue);
      expect(c.locked, isFalse);
      expect(keystore.authenticateCalls, 1);
    });

    test('a dismissed prompt leaves it locked, without an error', () async {
      final c = make();
      await c.init();
      keystore.cancelAuth = true;
      expect(await c.unlock(), isFalse);
      expect(c.locked, isTrue);
      expect(c.unlocking, isFalse);
    });
  });

  group('phone without a screen lock', () {
    test('cannot lock; one notice, once, never again', () async {
      keystore.secureLock = false;
      final c = make();
      await c.init();
      expect(c.locked, isFalse);
      expect(c.active, isFalse);
      expect(c.noticePending, isTrue);
      await c.noticeShown();
      expect(c.noticePending, isFalse);

      // Later sessions and focus changes do not repeat it.
      final again = make();
      await again.init();
      expect(again.noticePending, isFalse);
      await again.handleLifecycle(AppLifecycleState.paused);
      await again.handleLifecycle(AppLifecycleState.resumed);
      expect(again.noticePending, isFalse);
      expect(again.hidden, isFalse);
    });

    test('no notice when the user turned app lock off', () async {
      keystore.secureLock = false;
      await AppLockSettings(store).saveEnabled(false);
      final c = make();
      await c.init();
      expect(c.noticePending, isFalse);
    });

    test('setting a screen lock later makes the lock apply', () async {
      keystore.secureLock = false;
      final c = make();
      await c.init();
      await c.unlock();
      keystore.secureLock = true;
      await c.handleLifecycle(AppLifecycleState.paused);
      clock = clock.add(const Duration(minutes: 5));
      await c.handleLifecycle(AppLifecycleState.resumed);
      expect(c.locked, isTrue);
    });
  });

  group('lock screen', () {
    Future<(AppLockController, GlobalKey<NavigatorState>)> pump(
      WidgetTester t,
    ) async {
      final c = make();
      await c.init();
      final key = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          builder: (context, child) =>
              AppLockGate(controller: c, navigatorKey: key, child: child!),
          home: const Scaffold(body: Center(child: Text('secret terminal'))),
        ),
      );
      await t.pump();
      return (c, key);
    }

    testWidgets('covers the whole app, including dialogs, until unlocked', (
      t,
    ) async {
      keystore.cancelAuth = true; // the automatic prompt is dismissed
      final (c, key) = await pump(t);
      expect(find.text('PureShell is locked'), findsOneWidget);
      expect(keystore.authenticateCalls, 1, reason: 'asks right away, once');

      // A dialog opened underneath is covered as well.
      unawaited(
        showDialog<void>(
          context: key.currentContext!,
          builder: (_) => const AlertDialog(content: Text('dialog text')),
        ),
      );
      await t.pump();
      expect(find.text('PureShell is locked'), findsOneWidget);
      final lockBox = t.getRect(find.byType(ColoredBox).last);
      expect(lockBox.size, t.view.physicalSize / t.view.devicePixelRatio);

      keystore.cancelAuth = false;
      await t.tap(find.text('Unlock'));
      await t.pumpAndSettle();
      expect(find.text('PureShell is locked'), findsNothing);
      expect(c.locked, isFalse);
      expect(keystore.authenticateCalls, 2);
    });

    testWidgets('no endless prompt loop after a dismissed prompt', (t) async {
      keystore.cancelAuth = true;
      await pump(t);
      await t.pump(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      expect(keystore.authenticateCalls, 1);
    });

    testWidgets('the back button does not reveal the app', (t) async {
      keystore.cancelAuth = true;
      await pump(t);
      expect(await t.binding.handlePopRoute(), isTrue); // consumed
      expect(find.text('PureShell is locked'), findsOneWidget);
    });

    testWidgets('focus loss shows an opaque cover with no content', (t) async {
      final (c, _) = await pump(t);
      await c.unlock();
      await t.pumpAndSettle();
      expect(find.text('PureShell is locked'), findsNothing);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      await t.pump();
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(
        find.text('PureShell is locked'),
        findsNothing,
        reason: 'just a cover, not the lock prompt',
      );
    });

    testWidgets('the one-time notice appears once without a screen lock', (
      t,
    ) async {
      keystore.secureLock = false;
      await pump(t);
      await t.pumpAndSettle();
      expect(find.text('App lock needs a screen lock'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('App lock needs a screen lock'), findsNothing);
    });
  });
}
