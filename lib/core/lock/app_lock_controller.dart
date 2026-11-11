// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/widgets.dart';

import '../keys/keystore_api.dart';
import 'app_lock_settings.dart';

/// Decides when the app is locked and unlocks it with the system's biometric
/// / screen-lock prompt.
///
/// - Locked when the app starts and whenever it comes back after being in the
///   background for longer than the timeout.
/// - Covered (opaque) the moment the app loses focus, so the recents
///   transition never shows content, even before the lock applies.
/// - Does nothing when the phone has no secure screen lock; instead one
///   notice is requested, once.
class AppLockController extends ChangeNotifier {
  AppLockController(
    this._keystore,
    this._settings, {
    DateTime Function()? now,
    this.supported = true,
  }) : _now = now ?? DateTime.now;

  /// False on platforms with no lock prompt yet (the Windows build): never
  /// locks, never asks for the no-screen-lock notice.
  final bool supported;

  final KeystoreApi _keystore;
  final AppLockSettings _settings;
  final DateTime Function() _now;

  var _enabled = true;
  var _timeout = LockTimeout.oneMinute;
  var _secureLockScreen = false;
  var _locked = false;
  var _covered = false;
  var _unlocking = false;
  var _noticePending = false;
  DateTime? _leftAt;

  bool get enabled => _enabled;
  LockTimeout get timeout => _timeout;

  /// The phone has a PIN, pattern, password or biometric lock.
  bool get secureLockScreen => _secureLockScreen;

  /// Locking is on and possible.
  bool get active => supported && _enabled && _secureLockScreen;

  bool get locked => _locked;

  /// The app should hide its content (locked, or just lost focus).
  bool get hidden => _locked || _covered;

  bool get unlocking => _unlocking;

  /// True once, when locking is on but the phone has no screen lock. The UI
  /// shows the notice and calls [noticeShown].
  bool get noticePending => _noticePending;

  Future<void> init() async {
    _enabled = await _settings.loadEnabled();
    _timeout = await _settings.loadTimeout();
    await _refreshCapabilities();
    if (active) _locked = true;
    notifyListeners();
  }

  Future<void> _refreshCapabilities() async {
    if (!supported) return;
    _secureLockScreen = (await _keystore.capabilities()).secureLockScreen;
    if (_enabled && !_secureLockScreen && !_noticePending) {
      if (!await _settings.loadNoticeShown()) _noticePending = true;
    }
  }

  Future<void> noticeShown() async {
    _noticePending = false;
    await _settings.saveNoticeShown();
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _settings.saveEnabled(value);
    await _refreshCapabilities();
    if (!value) _locked = false;
    notifyListeners();
  }

  Future<void> setTimeout(LockTimeout value) async {
    _timeout = value;
    await _settings.saveTimeout(value);
    notifyListeners();
  }

  /// Feed with the app lifecycle.
  Future<void> handleLifecycle(AppLifecycleState state) async {
    // A fingerprint / screen-lock prompt takes focus away from the app; that
    // is not the user leaving it.
    if (PromptTracker.active.value > 0) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _covered = false;
        final left = _leftAt;
        _leftAt = null;
        if (left != null) {
          await _refreshCapabilities();
          if (active && _now().difference(left) >= _timeout.duration) {
            _locked = true;
          }
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _leftAt ??= _now();
        if (active) _covered = true;
    }
    notifyListeners();
  }

  /// Shows the system prompt. Returns true when unlocked; a dismissed prompt
  /// just leaves the app locked.
  Future<bool> unlock() async {
    if (!_locked || _unlocking) return !_locked;
    _unlocking = true;
    notifyListeners();
    try {
      await _keystore.authenticate();
      _locked = false;
      _covered = false;
      _leftAt = null;
      return true;
    } on KeystoreException {
      return false;
    } finally {
      _unlocking = false;
      notifyListeners();
    }
  }
}
