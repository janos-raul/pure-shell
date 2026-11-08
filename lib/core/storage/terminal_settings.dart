// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'secure_store.dart';

/// Small non-secret terminal preferences (kept in the same encrypted store so
/// the app needs no second storage mechanism).
class TerminalSettings {
  TerminalSettings(this._store);

  static const fontSizeKey = 'terminal.fontSize';

  /// About 60+ columns in portrait on a Pixel 7-sized screen.
  static const defaultFontSize = 11.0;
  static const minFontSize = 7.0;
  static const maxFontSize = 28.0;

  final SecureStore _store;

  static double clampFontSize(double size) =>
      size.clamp(minFontSize, maxFontSize);

  Future<double> loadFontSize() async {
    final raw = await _store.read(fontSizeKey);
    final value = raw == null ? null : double.tryParse(raw);
    if (value == null || value.isNaN) return defaultFontSize;
    return clampFontSize(value);
  }

  Future<void> saveFontSize(double size) =>
      _store.write(fontSizeKey, clampFontSize(size).toString());
}
