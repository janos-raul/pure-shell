// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';

import '../theme.dart';

import '../../core/keys/keystore_api.dart';
import '../../core/keys/ssh_key.dart';

/// "StrongBox" / "TEE" / "Software key" badge.
class SecurityBadge extends StatelessWidget {
  const SecurityBadge({super.key, required this.sshKey, this.level});

  final SshKey sshKey;

  /// The level to show (the live one if it differs from the stored one).
  final SecurityLevel? level;

  @override
  Widget build(BuildContext context) {
    final shown = level ?? sshKey.level;
    // Amber also for a Hello key whose TPM backing is not proven.
    final software =
        sshKey.isSoftware ||
        shown == SecurityLevel.software ||
        shown == SecurityLevel.hello;
    final label = sshKey.isSoftware ? 'Software key' : shown.label;
    // Outlined chip on black: green for hardware-backed keys, amber for
    // software keys. Never a fill.
    final color = software
        ? warningAmber
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}
