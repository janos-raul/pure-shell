// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/services.dart';

/// The system clipboard, for the terminal.
///
/// Reading happens only when the user taps Paste (never on open, never in the
/// background). Copying from the terminal marks the clip as sensitive on
/// Android 13+ (EXTRA_IS_SENSITIVE), so the system's clipboard preview does
/// not show terminal content; older versions get a normal copy. Nothing that is
/// read or copied is logged.
class TerminalClipboard {
  TerminalClipboard({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'eu.pureshell.app/clipboard';

  final MethodChannel _channel;

  /// Android 13+: EXTRA_IS_SENSITIVE. Windows (runner, window_channels.cpp):
  /// kept out of clipboard history (Win+V), cloud clipboard sync and
  /// clipboard monitors.
  Future<void> copySensitive(String text) async {
    try {
      await _channel.invokeMethod<void>('copy', {'text': text});
    } on MissingPluginException {
      // No native side (tests, other platforms): a normal copy.
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<String?> readText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}

/// Makes clipboard text safe to send as typed input: control characters other
/// than Tab and line breaks are dropped (an Escape in the text could end a
/// bracketed paste early and run what follows; Ctrl+C and friends would act as
/// keys), and line breaks become \r, what the Enter key sends.
String sanitizePaste(String text) {
  final out = StringBuffer();
  final units = text.runes.toList();
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    if (c == 0x0d) {
      out.writeCharCode(0x0d);
      if (i + 1 < units.length && units[i + 1] == 0x0a) i++;
    } else if (c == 0x0a) {
      out.writeCharCode(0x0d);
    } else if (c == 0x09 ||
        (c >= 0x20 && c != 0x7f && !(c >= 0x80 && c < 0xa0))) {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}
