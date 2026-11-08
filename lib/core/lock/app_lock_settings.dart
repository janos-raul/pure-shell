// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import '../storage/secure_store.dart';

/// How long the app may be in the background before it locks again.
enum LockTimeout {
  immediately(Duration.zero, 'Immediately'),
  oneMinute(Duration(minutes: 1), '1 minute'),
  fiveMinutes(Duration(minutes: 5), '5 minutes'),
  fifteenMinutes(Duration(minutes: 15), '15 minutes');

  const LockTimeout(this.duration, this.label);

  final Duration duration;
  final String label;
}

/// App lock preferences. On by default (it still only takes effect when the
/// phone has a secure screen lock), 1 minute timeout.
class AppLockSettings {
  AppLockSettings(this._store);

  static const enabledKey = 'lock.enabled';
  static const timeoutKey = 'lock.timeout';
  static const noticeShownKey = 'lock.noticeShown';

  final SecureStore _store;

  Future<bool> loadEnabled() async =>
      (await _store.read(enabledKey)) != 'false';

  Future<void> saveEnabled(bool value) =>
      _store.write(enabledKey, value.toString());

  Future<LockTimeout> loadTimeout() async {
    final raw = await _store.read(timeoutKey);
    return LockTimeout.values.asNameMap()[raw] ?? LockTimeout.oneMinute;
  }

  Future<void> saveTimeout(LockTimeout value) =>
      _store.write(timeoutKey, value.name);

  /// The one-time "can't lock without a screen lock" notice.
  Future<bool> loadNoticeShown() async =>
      (await _store.read(noticeShownKey)) == 'true';

  Future<void> saveNoticeShown() => _store.write(noticeShownKey, 'true');
}
