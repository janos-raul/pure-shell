// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';

import '../../core/platform_support.dart';
import '../theme.dart';

/// What the host list shows while there are no hosts: a short welcome with the
/// two ways to start and a link to the help. Not a separate screen.
class WelcomeView extends StatelessWidget {
  const WelcomeView({
    super.key,
    required this.hasKeys,
    required this.onAddHost,
    required this.onCreateKey,
    required this.onHelp,
  });

  /// With a key already made, "Create a key" is not offered.
  final bool hasKeys;
  final VoidCallback onAddHost;
  final VoidCallback onCreateKey;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '>_',
              style: monoStyle.copyWith(
                fontSize: 56,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome to Pure-Shell',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              windowsStub
                  ? 'Your hosts are saved on this computer only. Keys are made '
                        'by Windows Hello and can never leave this computer.'
                  : 'Your hosts are saved on this phone only. Keys are made '
                        'inside the phone and can never leave it.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton(onPressed: onAddHost, child: const Text('Add a host')),
            if (!hasKeys) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onCreateKey,
                child: const Text('Create a key'),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(onPressed: onHelp, child: const Text('How it works')),
          ],
        ),
      ),
    );
  }
}
