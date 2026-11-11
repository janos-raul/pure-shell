// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/keys/keystore_api.dart';
import 'package:pureshell/core/lock/app_lock_controller.dart';
import 'package:pureshell/core/lock/app_lock_settings.dart';
import 'package:pureshell/core/storage/secure_store.dart';

import 'fake_keystore.dart';

void main() {
  late FakeKeystore keystore;
  late MemorySecureStore store;
  late DateTime t;

  setUp(() {
    keystore = FakeKeystore();
    store = MemorySecureStore();
    t = DateTime(2026, 11, 11, 12);
  });

  /// A desktop controller, started and unlocked, inside fake time.
  AppLockController started(FakeAsync async, {LockTimeout? timeout}) {
    if (timeout != null) store.data[AppLockSettings.timeoutKey] = timeout.name;
    final c = AppLockController(
      keystore,
      AppLockSettings(store),
      now: () => t,
      desktop: true,
    );
    c.init();
    async.flushMicrotasks();
    expect(c.locked, isTrue, reason: 'locked at start, like Android');
    c.unlock();
    async.flushMicrotasks();
    expect(c.locked, isFalse);
    return c;
  }

  void event(AppLockController c, FakeAsync async, String e) {
    c.handleWindowEvent(e);
    async.flushMicrotasks();
  }

  test('alt-tab (focus and lifecycle changes) neither locks nor covers', () {
    fakeAsync((async) {
      final c = started(async);
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        c.handleLifecycle(s);
        async.flushMicrotasks();
        expect(c.hidden, isFalse, reason: '$s');
      }
      t = t.add(const Duration(hours: 1));
      c.handleLifecycle(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(c.locked, isFalse);
    });
  });

  test('Windows session lock locks at once; prompt only after unlock', () {
    fakeAsync((async) {
      final c = started(async);
      event(c, async, 'sessionLock');
      expect(c.locked, isTrue);
      expect(c.canPromptNow, isFalse); // not on the Windows lock screen
      event(c, async, 'sessionUnlock');
      expect(c.locked, isTrue);
      expect(c.canPromptNow, isTrue);
    });
  });

  test('minimised past the timeout locks, even before restoring', () {
    fakeAsync((async) {
      final c = started(async); // default timeout: 1 minute
      event(c, async, 'minimized');
      async.elapse(const Duration(seconds: 59));
      expect(c.locked, isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(c.locked, isTrue);
      expect(c.canPromptNow, isFalse);
      event(c, async, 'restored');
      expect(c.canPromptNow, isTrue);
    });
  });

  test('restored within the timeout stays unlocked', () {
    fakeAsync((async) {
      final c = started(async);
      event(c, async, 'minimized');
      async.elapse(const Duration(seconds: 30));
      t = t.add(const Duration(seconds: 30));
      event(c, async, 'restored');
      async.elapse(const Duration(minutes: 5));
      expect(c.locked, isFalse);
    });
  });

  test('restore checks the clock too (timer late after sleep)', () {
    fakeAsync((async) {
      final c = started(async, timeout: LockTimeout.fiveMinutes);
      event(c, async, 'minimized');
      t = t.add(const Duration(minutes: 10)); // wall clock moved, timer not
      event(c, async, 'restored');
      expect(c.locked, isTrue);
    });
  });

  test('"Immediately" locks as soon as the window is minimised', () {
    fakeAsync((async) {
      final c = started(async, timeout: LockTimeout.immediately);
      event(c, async, 'minimized');
      expect(c.locked, isTrue);
    });
  });

  test('without Windows Hello: no lock, no notice', () {
    fakeAsync((async) {
      keystore.secureLock = false; // also: canAuthenticate false
      final c = AppLockController(
        keystore,
        AppLockSettings(store),
        desktop: true,
      );
      c.init();
      async.flushMicrotasks();
      expect(c.active, isFalse);
      expect(c.locked, isFalse);
      expect(c.noticePending, isFalse);
      event(c, async, 'sessionLock');
      expect(c.locked, isFalse);
    });
  });

  test('Android ignores window events', () {
    fakeAsync((async) {
      final c = AppLockController(keystore, AppLockSettings(store));
      c.init();
      async.flushMicrotasks();
      c.unlock();
      async.flushMicrotasks();
      event(c, async, 'sessionLock');
      expect(c.locked, isFalse);
      expect(c.canPromptNow, isTrue);
    });
  });

  test('Remote Desktop: no Hello, so no lock, and the reason is known', () {
    fakeAsync((async) {
      final k = _SwitchableHello()..reason = 'remote';
      final c = AppLockController(k, AppLockSettings(store), desktop: true);
      c.init();
      async.flushMicrotasks();
      expect(c.active, isFalse);
      expect(c.locked, isFalse);
      expect(c.unavailableReason, 'remote');
    });
  });

  test('a Remote Desktop disconnect locks like a session lock', () {
    fakeAsync((async) {
      final c = started(async);
      event(c, async, 'sessionDisconnect');
      expect(c.locked, isTrue);
      expect(c.canPromptNow, isFalse);
    });
  });

  test('locked at the console, reconnected over RDP: the lock is lifted', () {
    fakeAsync((async) {
      final k = _SwitchableHello();
      final c = AppLockController(k, AppLockSettings(store), desktop: true);
      c.init();
      async.flushMicrotasks();
      expect(c.locked, isTrue);
      k.reason = 'remote'; // now connected over Remote Desktop
      event(c, async, 'sessionConnect');
      expect(c.locked, isFalse);
      expect(c.unavailableReason, 'remote');
    });
  });

  test('RDP session ends, back at the computer: locked, Hello unlocks', () {
    fakeAsync((async) {
      final k = _SwitchableHello()..reason = 'remote';
      final c = AppLockController(k, AppLockSettings(store), desktop: true);
      c.init();
      async.flushMicrotasks();
      expect(c.locked, isFalse); // over RDP: no lock
      event(c, async, 'sessionDisconnect');
      expect(c.locked, isFalse); // Hello still unavailable here
      k.reason = null; // signed in at the computer
      event(c, async, 'sessionConnect');
      expect(c.locked, isTrue);
      expect(c.canPromptNow, isTrue);
      c.unlock();
      async.flushMicrotasks();
      expect(c.locked, isFalse);
    });
  });
}

/// Windows Hello that can be taken away (Remote Desktop) and given back.
class _SwitchableHello extends FakeKeystore {
  String? reason;

  @override
  Future<KeystoreCapabilities> capabilities() async => KeystoreCapabilities(
    secureLockScreen: true,
    canAuthenticate: reason == null,
    authUnavailableReason: reason,
  );

  @override
  Future<void> authenticate({String title = '', String? subtitle}) async {
    if (reason != null) {
      throw const KeystoreException(KeystoreErrorKind.unavailable);
    }
  }
}
