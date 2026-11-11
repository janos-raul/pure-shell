// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';

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
///
/// Desktop ([desktop], the Windows build) works differently, because a
/// desktop window loses the focus all the time (alt-tab):
///
/// - Focus and app lifecycle changes are ignored ([handleLifecycle]).
/// - Locked at once when Windows locks the session (Win+L, sleep), and when
///   the window has been minimised for longer than the timeout
///   ([handleWindowEvent]).
/// - Possible only with Windows Hello (`canAuthenticate`); no notice, the
///   setting explains it.
/// - The unlock prompt is only started while the window can be seen
///   ([canPromptNow]): not on the Windows lock screen, not while minimised.
class AppLockController extends ChangeNotifier {
  AppLockController(
    this._keystore,
    this._settings, {
    DateTime Function()? now,
    this.desktop = false,
  }) : _now = now ?? DateTime.now;

  /// Desktop rules (see the class comment).
  final bool desktop;

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

  // Desktop window state.
  String? _unavailableReason;
  var _sessionLocked = false;
  var _lockOnReturn = false;
  var _minimized = false;
  DateTime? _minimizedAt;
  Timer? _minimizedTimer;

  bool get enabled => _enabled;
  LockTimeout get timeout => _timeout;

  /// The phone has a PIN, pattern, password or biometric lock.
  bool get secureLockScreen => _secureLockScreen;

  /// Locking is on and possible.
  bool get active => _enabled && _secureLockScreen;

  /// Desktop: why Windows Hello cannot verify the user now (`remote` over
  /// Remote Desktop, `notConfigured`, ...), or null when it can.
  String? get unavailableReason => _unavailableReason;

  /// Whether the unlock prompt may be shown now (desktop: only while the
  /// window is visible and Windows is not locked).
  bool get canPromptNow => !desktop || (!_sessionLocked && !_minimized);

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
    final caps = await _keystore.capabilities();
    // Desktop: the lock needs Windows Hello to unlock.
    _secureLockScreen = desktop ? caps.canAuthenticate : caps.secureLockScreen;
    if (desktop) {
      _unavailableReason = caps.canAuthenticate
          ? null
          : (caps.authUnavailableReason ?? 'notPresent');
      return; // no notice: the setting and the lock screen say why
    }
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

  /// Desktop window events from the runner (window_channels.cpp):
  /// `sessionLock`, `sessionUnlock`, `minimized`, `restored`.
  Future<void> handleWindowEvent(String event) async {
    if (!desktop) return;
    switch (event) {
      // A Remote Desktop disconnect often comes without a lock event.
      case 'sessionLock' || 'sessionDisconnect':
        _sessionLocked = true;
        // Remembered even when Hello is not available right now (over
        // Remote Desktop): back at the computer the app must lock.
        _lockOnReturn = _enabled;
        if (active) _locked = true;
      // Back at the screen, locally or over Remote Desktop.
      case 'sessionUnlock' || 'sessionConnect':
        _sessionLocked = false;
        await _refreshCapabilities();
        if (_unavailableReason == 'remote') {
          // Remote Desktop: Windows already asked for the account's
          // password and Windows Hello cannot be used there, so the app lock
          // does not apply (the user's decision).
          _locked = false;
        } else if (_lockOnReturn && active) {
          _locked = true;
        }
        _lockOnReturn = false;
      case 'minimized':
        _minimized = true;
        _minimizedAt = _now();
        _minimizedTimer?.cancel();
        if (active) {
          if (_timeout.duration == Duration.zero) {
            _locked = true;
          } else {
            // Lock while still minimised, so the window never shows the
            // terminal again once the timeout has passed.
            _minimizedTimer = Timer(_timeout.duration, () {
              if (_minimized && active) {
                _locked = true;
                notifyListeners();
              }
            });
          }
        }
      case 'restored':
        _minimized = false;
        _minimizedTimer?.cancel();
        final at = _minimizedAt;
        _minimizedAt = null;
        if (active &&
            at != null &&
            _now().difference(at) >= _timeout.duration) {
          _locked = true;
        }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _minimizedTimer?.cancel();
    super.dispose();
  }

  /// Feed with the app lifecycle. Ignored on the desktop, where losing the
  /// focus (alt-tab) is no reason to cover or lock.
  Future<void> handleLifecycle(AppLifecycleState state) async {
    if (desktop) return;
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
      // Desktop: Hello may have come back (at the console after Remote
      // Desktop) or gone; the lock screen shows why it cannot unlock.
      if (desktop) await _refreshCapabilities();
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
