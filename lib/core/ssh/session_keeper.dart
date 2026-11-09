// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/services.dart';

/// Keeps connected sessions alive while the app is in the background.
///
/// Android blocks the network of an app a few seconds after it leaves the
/// screen and destroys its open TCP connections, unless the app runs a
/// foreground service. The native service is started while at least one
/// session is connected and stopped when the last one closes. Its
/// notification shows the number of sessions and nothing else (no hostnames,
/// usernames or terminal content).
///
/// This class only counts: sessions register with [opened] and [closed], and
/// the count is pushed to the native side. "Disconnect all" in the
/// notification arrives as a call from the native side and closes every
/// registered session, whether or not the app is locked.
class SessionKeeper {
  SessionKeeper({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  /// The one used by the app.
  static final instance = SessionKeeper();

  static const channelName = 'eu.pureshell.app/sessions';

  final MethodChannel _channel;
  final _sessions = <Object, void Function()>{};
  var _enabled = true;

  /// Whether the keep-alive setting is on.
  bool get enabled => _enabled;

  /// Connected sessions right now.
  int get count => _sessions.length;

  /// Turns the setting on or off. Off stops the service at once; sessions
  /// stay connected for as long as Android lets the app run.
  Future<void> setEnabled(bool value) {
    _enabled = value;
    return _push();
  }

  /// A session is connected. [disconnect] ends it (used by "Disconnect all").
  Future<void> opened(Object token, void Function() disconnect) {
    _sessions[token] = disconnect;
    return _push();
  }

  /// The session is over (closed, lost or the screen is gone).
  Future<void> closed(Object token) {
    if (_sessions.remove(token) == null) return Future.value();
    return _push();
  }

  Future<void> _push() =>
      _invoke<void>('update', {'count': _enabled ? _sessions.length : 0});

  /// Whether the notification may be shown (always true before Android 13).
  Future<bool> notificationsAllowed() async =>
      await _invoke<bool>('notificationsAllowed') ?? true;

  /// Asks for the notification permission (Android 13+). Returns the result.
  Future<bool> requestNotifications() async =>
      await _invoke<bool>('requestNotifications') ?? false;

  Future<T?> _invoke<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null; // no native side (tests, other platforms)
    }
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'disconnectAll') return;
    // Copy: each disconnect closes its session, which removes it.
    for (final disconnect in _sessions.values.toList()) {
      disconnect();
    }
  }
}
