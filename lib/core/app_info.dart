// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/services.dart';

/// Version and build number of the installed app, read from the app itself
/// (no extra package): "1.0.0" and "8" for version 1.0.0+8.
class AppVersion {
  const AppVersion(this.name, this.build);

  final String name;
  final String build;

  @override
  String toString() => 'Version $name ($build)';
}

class AppInfo {
  AppInfo({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'eu.pureshell.app/app_info';

  final MethodChannel _channel;

  /// Null when the native side is not there (tests).
  Future<AppVersion?> version() async {
    try {
      final map = await _channel.invokeMapMethod<String, String>('version');
      final name = map?['name'];
      final build = map?['build'];
      if (name == null || build == null) return null;
      return AppVersion(name, build);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
