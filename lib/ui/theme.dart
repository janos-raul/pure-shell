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
    error: Color(0xFFFF5555),
    onError: _black,
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
    textTheme: ThemeData.dark().textTheme.apply(
      bodyColor: _green,
      displayColor: _green,
      fontFamily: 'monospace',
    ),
  );
}

/// Light-gray text on black with the standard ANSI colors (the xterm default
/// palette): what most terminals look like.
const standardTerminalTheme = TerminalTheme(
  cursor: Color(0xFFCCCCCC),
  selection: Color(0x80CCCCCC),
  foreground: Color(0xFFCCCCCC),
  background: Color(0xFF000000),
  black: Color(0xFF000000),
  red: Color(0xFFCD3131),
  green: Color(0xFF0DBC79),
  yellow: Color(0xFFE5E510),
  blue: Color(0xFF2472C8),
  magenta: Color(0xFFBC3FBC),
  cyan: Color(0xFF11A8CD),
  white: Color(0xFFE5E5E5),
  brightBlack: Color(0xFF666666),
  brightRed: Color(0xFFF14C4C),
  brightGreen: Color(0xFF23D18B),
  brightYellow: Color(0xFFF5F543),
  brightBlue: Color(0xFF3B8EEA),
  brightMagenta: Color(0xFFD670D6),
  brightCyan: Color(0xFF29B8DB),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: Color(0xFF31FF26),
  searchHitForeground: Color(0xFF000000),
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
