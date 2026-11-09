// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';

/// Row of keys missing from the Android soft keyboard. Ctrl is a sticky
/// modifier: tap it, then the next key is sent with Ctrl applied.
class ExtraKeysRow extends StatelessWidget {
  const ExtraKeysRow({
    super.key,
    required this.ctrlActive,
    required this.onCtrl,
    required this.onKey,
    required this.onText,
    required this.onBox,
    this.boxOpen = false,
  });

  /// The command-line box button was tapped (open or close it).
  final VoidCallback onBox;

  /// While the box is open the keys act on the box: Tab and Ctrl are disabled.
  final bool boxOpen;

  final bool ctrlActive;
  final VoidCallback onCtrl;

  /// Named keys: 'esc', 'tab', 'up', 'down', 'left', 'right'.
  final void Function(String name) onKey;

  /// Literal characters: '|', '~', '/'.
  final void Function(String text) onText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(
      Object label,
      VoidCallback onTap, {
      bool active = false,
      bool enabled = true,
      String? tooltip,
    }) {
      final color = active ? scheme.onPrimary : null;
      Widget face = label is IconData
          ? Icon(label, size: 20, color: color)
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label as String,
                style: TextStyle(fontSize: 15, color: color),
              ),
            );
      if (tooltip != null) face = Tooltip(message: tooltip, child: face);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Opacity(
            opacity: enabled ? 1 : 0.35,
            child: Material(
              color: active ? scheme.primary : const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: enabled ? onTap : null,
                child: SizedBox(
                  height: 40,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: face,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          key('Esc', () => onKey('esc')),
          key('Tab', () => onKey('tab'), enabled: !boxOpen),
          key('Ctrl', onCtrl, active: ctrlActive, enabled: !boxOpen),
          key('←', () => onKey('left')),
          key('↑', () => onKey('up')),
          key('↓', () => onKey('down')),
          key('→', () => onKey('right')),
          key('|', () => onText('|')),
          key('~', () => onText('~')),
          key('/', () => onText('/')),
          key(Icons.edit_note, onBox, active: boxOpen, tooltip: 'Command line'),
        ],
      ),
    );
  }
}
