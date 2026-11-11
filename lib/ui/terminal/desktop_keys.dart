// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/services.dart';

/// What the desktop terminal does with a key press before xterm sees it.
sealed class DesktopKeyAction {
  const DesktopKeyAction();
}

class CopyAction extends DesktopKeyAction {
  const CopyAction();
}

class PasteAction extends DesktopKeyAction {
  const PasteAction();
}

/// Font size: +1 / -1 step, or back to the default (0).
class ZoomAction extends DesktopKeyAction {
  const ZoomAction(this.step);
  final int step;
}

/// Text sent as it is: an AltGr character (Windows reports AltGr as
/// Ctrl+Alt), or ESC + the character for Alt+key (xterm itself would send
/// the upper-case letter, so Alt+b and Alt+B would be the same).
class TypeAction extends DesktopKeyAction {
  const TypeAction(this.text);
  final String text;
}

final _zoomIn = {
  LogicalKeyboardKey.equal,
  LogicalKeyboardKey.add,
  LogicalKeyboardKey.numpadAdd,
};
final _zoomOut = {LogicalKeyboardKey.minus, LogicalKeyboardKey.numpadSubtract};
final _zoomReset = {LogicalKeyboardKey.digit0, LogicalKeyboardKey.numpad0};

/// The desktop shortcuts, like Windows Terminal:
///
/// - Ctrl+Shift+C copy, Ctrl+Shift+V and Shift+Insert paste;
/// - Ctrl+= / Ctrl++ / Ctrl+- / Ctrl+0 font size;
/// - AltGr characters typed as text.
///
/// Everything else (Ctrl+A, Ctrl+V, Ctrl+C, Alt+b, ...) returns null and goes
/// to the shell as the normal control / meta key.
DesktopKeyAction? desktopKeyAction(
  LogicalKeyboardKey key, {
  required bool ctrl,
  required bool shift,
  required bool alt,
  String? character,
}) {
  if (ctrl && shift && !alt) {
    if (key == LogicalKeyboardKey.keyC) return const CopyAction();
    if (key == LogicalKeyboardKey.keyV) return const PasteAction();
  }
  if (shift && !ctrl && !alt && key == LogicalKeyboardKey.insert) {
    return const PasteAction();
  }
  if (ctrl && !alt) {
    // Ctrl+Shift+= is Ctrl++ on US layouts; Ctrl+Shift+- (^_) is readline's
    // undo and stays with the shell.
    if (_zoomIn.contains(key)) return const ZoomAction(1);
    if (!shift && _zoomOut.contains(key)) return const ZoomAction(-1);
    if (!shift && _zoomReset.contains(key)) return const ZoomAction(0);
  }
  if (alt && _printable(character)) {
    // Ctrl+Alt = AltGr: the character itself. Alt alone: meta (ESC prefix).
    return TypeAction(ctrl ? character! : '\x1b$character');
  }
  return null;
}

bool _printable(String? s) {
  if (s == null || s.isEmpty) return false;
  final c = s.codeUnitAt(0);
  return c >= 0x20 && c != 0x7f;
}
