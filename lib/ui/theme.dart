// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../core/storage/terminal_settings.dart';

/// Phosphor green on black.
const _green = Color(0xFF33FF66);
const _dimGreen = Color(0xFF1F9940);
const _black = Color(0xFF000000);
const _panel = Color(0xFF0A120C);

/// THE COLOR RULE: red (errors, destructive actions) is only ever used on the
/// black background, as text, outline or icon. Never as a fill, and never on
/// or inside a green fill. Warnings use amber the same way.
const errorRed = Color(0xFFFF5555);
const warningAmber = Color(0xFFFFB300);

/// A destructive text button: red text on black.
ButtonStyle destructiveTextStyle() =>
    TextButton.styleFrom(foregroundColor: errorRed);

/// A destructive outlined button: red text and red outline on black.
ButtonStyle destructiveOutlineStyle() => OutlinedButton.styleFrom(
  foregroundColor: errorRed,
  side: const BorderSide(color: errorRed),
);

/// For technical values: hostnames, user@host:port, fingerprints, key lines.
const monoStyle = TextStyle(fontFamily: 'monospace');

ThemeData pureShellTheme() {
  const scheme = ColorScheme.dark(
    primary: _green,
    onPrimary: _black,
    secondary: _dimGreen,
    onSecondary: _black,
    surface: _black,
    onSurface: _green,
    onSurfaceVariant: Color(0xFF29CC52),
    surfaceContainerHighest: _panel,
    surfaceContainerHigh: _panel,
    surfaceContainer: _panel,
    surfaceContainerLow: _black,
    outline: _dimGreen,
    outlineVariant: Color(0xFF14501F),
    error: errorRed,
    onError: _black,
    // Nothing may fill with red: should a widget ever use these, it gets a
    // black fill with red text.
    errorContainer: _black,
    onErrorContainer: errorRed,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: _black,
    canvasColor: _black,
    dialogTheme: const DialogThemeData(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: _dimGreen),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _black,
      foregroundColor: _green,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardThemeData(
      color: _panel,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: const Color(0xFF14501F),
    // Proportional font for the UI; technical values use [monoStyle].
    textTheme: ThemeData.dark().textTheme.apply(
      bodyColor: _green,
      displayColor: _green,
    ),
  );
}

/// Windows Terminal's "Campbell" scheme.
const standardTerminalTheme = TerminalTheme(
  cursor: Color(0xFFFFFFFF),
  selection: Color(0x80FFFFFF),
  foreground: Color(0xFFCCCCCC),
  background: Color(0xFF0C0C0C),
  black: Color(0xFF0C0C0C),
  red: Color(0xFFC50F1F),
  green: Color(0xFF13A10E),
  yellow: Color(0xFFC19C00),
  blue: Color(0xFF0037DA),
  magenta: Color(0xFF881798),
  cyan: Color(0xFF3A96DD),
  white: Color(0xFFCCCCCC),
  brightBlack: Color(0xFF767676),
  brightRed: Color(0xFFE74856),
  brightGreen: Color(0xFF16C60C),
  brightYellow: Color(0xFFF9F1A5),
  brightBlue: Color(0xFF3B78FF),
  brightMagenta: Color(0xFFB4009E),
  brightCyan: Color(0xFF61D6D6),
  brightWhite: Color(0xFFF2F2F2),
  searchHitBackground: Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: Color(0xFF31FF26),
  searchHitForeground: Color(
    0xFF000000,
  ), // Bold text in a normal color is drawn bright, like Windows Terminal
  // (needs our xterm fork, see docs/xterm-fork.md).
  boldIsBright: true,
);

TerminalTheme terminalThemeFor(TerminalColors colors) => switch (colors) {
  TerminalColors.standard => standardTerminalTheme,
  TerminalColors.phosphor => phosphorTerminalTheme,
};

/// Green text on black; the ANSI colours stay distinguishable so htop, vim and
/// `ls --color` remain readable.
const phosphorTerminalTheme = TerminalTheme(
  cursor: Color(0xFF66FF88),
  selection: Color(0x8033FF66),
  foreground: _green,
  background: _black,
  black: Color(0xFF000000),
  red: Color(0xFFCD3131),
  green: Color(0xFF33FF66),
  yellow: Color(0xFFE5E510),
  blue: Color(0xFF3B8EEA),
  magenta: Color(0xFFBC3FBC),
  cyan: Color(0xFF11A8CD),
  white: Color(0xFFB8FFC8),
  brightBlack: Color(0xFF4D7A58),
  brightRed: Color(0xFFF14C4C),
  brightGreen: Color(0xFF7DFF9A),
  brightYellow: Color(0xFFF5F543),
  brightBlue: Color(0xFF5FA8FF),
  brightMagenta: Color(0xFFD670D6),
  brightCyan: Color(0xFF29B8DB),
  brightWhite: Color(0xFFE8FFEE),
  searchHitBackground: Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: Color(0xFF31FF26),
  searchHitForeground: Color(0xFF000000),
);
