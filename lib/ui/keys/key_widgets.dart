// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';

import '../../core/keys/keystore_api.dart';
import '../../core/keys/ssh_key.dart';

/// "StrongBox" / "TEE" / "Software key" badge.
class SecurityBadge extends StatelessWidget {
  const SecurityBadge({super.key, required this.sshKey});

  final SshKey sshKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final software =
        sshKey.isSoftware || sshKey.level == SecurityLevel.software;
    final label = sshKey.isSoftware ? 'Software key' : sshKey.level.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: software ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: software ? scheme.onErrorContainer : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
