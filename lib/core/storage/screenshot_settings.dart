// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'secure_store.dart';

/// Turns the Android window's FLAG_SECURE on or off.
abstract class WindowSecurity {
  Future<void> setSecure(bool secure);
}

class PlatformWindowSecurity implements WindowSecurity {
  const PlatformWindowSecurity();

  static const _channel = MethodChannel('eu.pureshell.app/window');

  @override
  Future<void> setSecure(bool secure) =>
      _channel.invokeMethod<void>('setSecure', {'secure': secure});
}

/// Whether screenshots, screen recording and the recent-apps preview are
/// allowed. Off by default: the window is secure (FLAG_SECURE) from the moment
/// it is created, and only an explicit choice lifts that.
class ScreenshotSettings extends ChangeNotifier {
  ScreenshotSettings(this._store, [WindowSecurity? window])
    : _window = window ?? const PlatformWindowSecurity();

  static const allowKey = 'privacy.allowScreenshots';

  final SecureStore _store;
  final WindowSecurity _window;
  bool _allowed = false;

  bool get allowed => _allowed;

  /// Reads the stored choice and applies it to the window.
  Future<void> init() async {
    _allowed = (await _store.read(allowKey)) == 'true';
    await _apply();
  }

  Future<void> setAllowed(bool value) async {
    _allowed = value;
    notifyListeners();
    await _store.write(allowKey, value.toString());
    await _apply();
  }

  Future<void> _apply() async {
    try {
      await _window.setSecure(!_allowed);
    } on MissingPluginException {
      // No native side (tests, other platforms): nothing to apply.
    }
  }
}
