// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/services.dart';

/// Opens the Android share sheet with [text]. Only ever used for public keys.
Future<void> shareText(String text) async {
  try {
    await const MethodChannel('eu.pureshell.app/share')
        .invokeMethod<void>('shareText', {'text': text});
  } on MissingPluginException {
    // Not on Android (tests): nothing to share with.
  }
}
