// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';

import '../../core/storage/terminal_settings.dart';

/// Pinch-to-zoom for a font size. Uses a plain Listener, which takes no part
/// in the gesture arena, so one-finger scrolling and selection in the child
/// keep working.
class PinchZoom extends StatefulWidget {
  const PinchZoom({
    super.key,
    required this.value,
    this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    required this.child,
  });

  /// Current font size.
  final double value;

  /// Called once when a pinch begins (the second finger touches down).
  final VoidCallback? onChangeStart;

  /// Called while pinching, with the new (clamped, half-point) size.
  final ValueChanged<double> onChanged;

  /// Called once when the second finger lifts, with the final size.
  final ValueChanged<double> onChangeEnd;

  final Widget child;

  @override
  State<PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<PinchZoom> {
  final _pointers = <int, Offset>{};
  double? _startDistance;
  var _startSize = TerminalSettings.defaultFontSize;
  var _current = TerminalSettings.defaultFontSize;

  double _distance() {
    final points = _pointers.values.take(2).toList();
    return (points[0] - points[1]).distance;
  }

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _startDistance = _distance();
      _startSize = _current = widget.value;
      widget.onChangeStart?.call();
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final start = _startDistance;
    if (_pointers.length < 2 || start == null || start < 1) return;
    final raw = _startSize * _distance() / start;
    final size = (TerminalSettings.clampFontSize(raw) * 2).round() / 2;
    if (size != _current) {
      _current = size;
      widget.onChanged(size);
    }
  }

  void _end(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2 && _startDistance != null) {
      _startDistance = null;
      widget.onChangeEnd(_current);
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _end,
    onPointerCancel: _end,
    child: widget.child,
  );
}
