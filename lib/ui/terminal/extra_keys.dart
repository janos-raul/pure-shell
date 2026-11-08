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
  });

  final bool ctrlActive;
  final VoidCallback onCtrl;

  /// Named keys: 'esc', 'tab', 'up', 'down', 'left', 'right'.
  final void Function(String name) onKey;

  /// Literal characters: '|', '~', '/'.
  final void Function(String text) onText;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, VoidCallback onTap, {bool active = false}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Material(
            color: active ? Colors.teal : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              child: SizedBox(
                height: 40,
                child: Center(
                  child: Text(label, style: const TextStyle(fontSize: 15)),
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
          key('Tab', () => onKey('tab')),
          key('Ctrl', onCtrl, active: ctrlActive),
          key('←', () => onKey('left')),
          key('↑', () => onKey('up')),
          key('↓', () => onKey('down')),
          key('→', () => onKey('right')),
          key('|', () => onText('|')),
          key('~', () => onText('~')),
          key('/', () => onText('/')),
        ],
      ),
    );
  }
}
