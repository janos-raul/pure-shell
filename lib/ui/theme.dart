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

/// Console look: body text is light grey like a shell (the same grey as the
/// standard terminal scheme), green is the accent: titles, icons, buttons,
/// the selected state.
const _text = Color(0xFFCCCCCC);
const _textDim = Color(0xFF8C8C8C);

/// THE COLOR RULE: red (errors, destructive actions) is only ever used on the
/// black background, as text, outline or icon. Never as a fill, and never on
/// or inside a green fill. Warnings use amber the same way.
const errorRed = Color(0xFFFF5555);
const warningAmber = Color(0xFFFFB300);

/// Amber accent for the key / password icons and the like (icon only, on
/// black). The same amber as warnings.
const accentAmber = warningAmber;

/// Console blue for emphasis: bold labels and section headers (like the blue
/// directories in a shell listing). Text only, on black.
const emphasisBlue = Color(0xFF5FA8FF);

/// Tone for the small icons in menus: softer than the bright green.
const menuIconColor = Color(0xFF29CC52);

/// A destructive text button: red text on black.
ButtonStyle destructiveTextStyle() =>
    TextButton.styleFrom(foregroundColor: errorRed);

/// A destructive outlined button: red text and red outline on black.
ButtonStyle destructiveOutlineStyle() => OutlinedButton.styleFrom(
  foregroundColor: errorRed,
  side: const BorderSide(color: errorRed),
);

/// A text button used as a link inside content: its text lines up with the
/// text around it (no button padding on the left).
ButtonStyle linkButtonStyle() => TextButton.styleFrom(
  padding: const EdgeInsets.symmetric(vertical: 12),
  alignment: Alignment.centerLeft,
  minimumSize: const Size(48, 48),
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
    onSurface: _text,
    onSurfaceVariant: _textDim,
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
    // Selected segments use the same bright green fill as buttons (one green
    // fill everywhere), unselected ones are outlined.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _green : _black,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _black : _green,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: _dimGreen)),
      ),
    ),
    // Off must not look like on: a dim thumb on an outlined track; on is a
    // bright track with a black thumb.
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? _green : _black,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? _green : _dimGreen,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? _black : _dimGreen,
      ),
    ),
    dividerColor: const Color(0xFF14501F),
    // Proportional font for the UI; technical values use [monoStyle].
    iconTheme: const IconThemeData(color: _green),
    textTheme: ThemeData.dark().textTheme
        .apply(bodyColor: _text, displayColor: _text)
        .copyWith(
          headlineSmall: const TextStyle(color: _green),
          titleLarge: const TextStyle(color: _green),
          titleMedium: const TextStyle(color: emphasisBlue),
          titleSmall: const TextStyle(color: emphasisBlue),
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
