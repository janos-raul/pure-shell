// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';

/// Compile-time test switches that must never reach a release build.
///
/// Returns a user-facing problem description, or null when the build is fine.
String? buildFlagProblem({
  required bool releaseMode,
  required bool allowSoftwareKeystore,
  required bool forceSoftwareKeys,
}) {
  if (!releaseMode) return null;
  final flags = [
    if (allowSoftwareKeystore) 'PURESHELL_ALLOW_SOFTWARE_KEYSTORE',
    if (forceSoftwareKeys) 'PURESHELL_FORCE_SOFTWARE_KEYS',
  ];
  if (flags.isEmpty) return null;
  return 'This is a release build made with a test-only switch '
      '(${flags.join(', ')}). Those switches weaken key protection and exist '
      'for emulator testing only. Rebuild without them.';
}

/// Shown instead of the app when [buildFlagProblem] finds a problem.
class BuildErrorApp extends StatelessWidget {
  const BuildErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'PureShell refuses to start',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
