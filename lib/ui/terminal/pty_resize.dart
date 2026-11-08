// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';

/// Sends PTY size changes to the server without flooding it.
///
/// Every size change makes the remote shell redraw (new prompt lines), so:
/// - nothing is sent while [hold] is active (a pinch-zoom in progress);
///   [release] sends the final size once;
/// - otherwise changes are debounced by [delay], so a burst (keyboard
///   animation, rotation) results in one send;
/// - a size equal to the last one sent is never sent again.
class PtyResizeCoalescer {
  PtyResizeCoalescer({
    required this.send,
    this.delay = const Duration(milliseconds: 150),
  });

  final void Function(int columns, int rows) send;
  final Duration delay;

  ({int columns, int rows})? _lastSent;
  ({int columns, int rows})? _pending;
  Timer? _timer;
  var _holding = false;
  var _disposed = false;

  /// The server already has this size (the shell was opened with it).
  void markSent(int columns, int rows) {
    _lastSent = (columns: columns, rows: rows);
  }

  /// The terminal now has this size.
  void request(int columns, int rows) {
    if (_disposed) return;
    _pending = (columns: columns, rows: rows);
    if (_holding) return;
    _timer?.cancel();
    _timer = Timer(delay, _flush);
  }

  /// Start of a gesture (pinch): collect changes, send none.
  void hold() {
    _holding = true;
    _timer?.cancel();
  }

  /// End of the gesture: send the final size right away, once.
  void release() {
    _holding = false;
    _timer?.cancel();
    _flush();
  }

  void _flush() {
    _timer = null;
    final size = _pending;
    _pending = null;
    if (_disposed || size == null || size == _lastSent) return;
    if (size.columns <= 0 || size.rows <= 0) return;
    _lastSent = size;
    send(size.columns, size.rows);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
