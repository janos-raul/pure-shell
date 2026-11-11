// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/services.dart';

/// Window events of the Windows build (runner: window_channels.cpp):
/// `sessionLock`, `sessionUnlock`, `minimized`, `restored`.
class WindowEvents {
  WindowEvents._();

  static const channelName = 'eu.pureshell.app/window_events';

  static void listen(void Function(String event) onEvent) {
    const MethodChannel(channelName).setMethodCallHandler((call) async {
      onEvent(call.method);
    });
  }
}
