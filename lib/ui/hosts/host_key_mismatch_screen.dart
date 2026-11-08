// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';

import '../../core/hosts/host.dart';
import '../../core/hosts/known_hosts.dart';

/// Full-screen hard block shown when the server's host key differs from the
/// trusted one. There is deliberately no way to continue from here: the user
/// has to remove the old key in the host's settings first.
class HostKeyMismatchScreen extends StatelessWidget {
  const HostKeyMismatchScreen({
    super.key,
    required this.host,
    required this.stored,
    required this.presented,
  });

  final Host host;
  final HostKey? stored;
  final HostKey? presented;

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13);
    return Scaffold(
      backgroundColor: const Color(0xFF3B0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7A1212),
        title: const Text('Connection blocked'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.gpp_bad, size: 72, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              'HOST KEY HAS CHANGED',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              '${host.hostname}:${host.port} presented a different key than '
              'the one you trusted. Someone may be intercepting the '
              'connection, or the server was reinstalled. No password was '
              'sent.',
            ),
            const SizedBox(height: 24),
            const Text(
              'Trusted key (stored)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(stored?.type ?? 'unknown'),
            SelectableText(stored?.fingerprint ?? 'unknown', style: mono),
            const SizedBox(height: 16),
            const Text(
              'Key presented now',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(presented?.type ?? 'unknown'),
            SelectableText(presented?.fingerprint ?? 'unknown', style: mono),
            const SizedBox(height: 24),
            const Text(
              'If you are sure the change is legitimate, verify the new '
              'fingerprint with the server administrator, then remove the old '
              'key under Edit host > Trusted host key and connect again.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
