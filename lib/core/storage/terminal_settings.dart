// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import '../platform_support.dart';
import 'secure_store.dart';

/// Terminal colour scheme.
enum TerminalColors {
  standard('Default', 'Windows Terminal "Campbell" colors'),
  phosphor('Phosphor green', 'Green on black');

  const TerminalColors(this.label, this.description);

  final String label;
  final String description;
}

/// How the soft keyboard talks to the terminal.
enum InputMode {
  direct(
    'Direct (key by key)',
    'Every character is sent as soon as it is typed.',
  ),
  composing(
    'Composing (IME words)',
    'The keyboard keeps a word until it is done (needed for Chinese, '
        'Japanese and Korean).',
  );

  const InputMode(this.label, this.description);

  final String label;
  final String description;
}

/// Small non-secret terminal preferences (kept in the same encrypted store so
/// the app needs no second storage mechanism).
class TerminalSettings {
  TerminalSettings(this._store);

  static const fontSizeKey = 'terminal.fontSize';
  static const colorsKey = 'terminal.colors';
  static const inputModeKey = 'terminal.inputMode';
  static const keepSessionsKey = 'connection.keepSessions';
  static const notificationAskedKey = 'connection.notificationAsked';

  /// About 60+ columns in portrait on a Pixel 7-sized screen.
  static const defaultFontSize = 11.0;

  /// Desktop monitors: about 120 columns in a 1280 px wide window.
  static const desktopDefaultFontSize = 14.0;

  /// The size used until the user zooms (and for Ctrl+0).
  static double get initialFontSize =>
      windowsStub ? desktopDefaultFontSize : defaultFontSize;

  static const minFontSize = 7.0;
  static const maxFontSize = 28.0;

  final SecureStore _store;

  static double clampFontSize(double size) =>
      size.clamp(minFontSize, maxFontSize);

  Future<double> loadFontSize() async {
    final raw = await _store.read(fontSizeKey);
    final value = raw == null ? null : double.tryParse(raw);
    if (value == null || value.isNaN) return initialFontSize;
    return clampFontSize(value);
  }

  Future<void> saveFontSize(double size) =>
      _store.write(fontSizeKey, clampFontSize(size).toString());

  Future<TerminalColors> loadColors() async {
    final raw = await _store.read(colorsKey);
    for (final c in TerminalColors.values) {
      if (c.name == raw) return c;
    }
    return TerminalColors.standard;
  }

  Future<void> saveColors(TerminalColors colors) =>
      _store.write(colorsKey, colors.name);

  Future<InputMode> loadInputMode() async {
    final raw = await _store.read(inputModeKey);
    for (final m in InputMode.values) {
      if (m.name == raw) return m;
    }
    return InputMode.direct;
  }

  Future<void> saveInputMode(InputMode mode) =>
      _store.write(inputModeKey, mode.name);

  /// Keep connected sessions alive in the background (foreground service with
  /// a notification). On by default.
  Future<bool> loadKeepSessions() async =>
      (await _store.read(keepSessionsKey)) != 'false';

  Future<void> saveKeepSessions(bool keep) =>
      _store.write(keepSessionsKey, keep.toString());

  /// Whether the notification permission was explained and asked for once.
  Future<bool> loadNotificationAsked() async =>
      (await _store.read(notificationAskedKey)) == 'true';

  Future<void> saveNotificationAsked() =>
      _store.write(notificationAskedKey, 'true');
}
