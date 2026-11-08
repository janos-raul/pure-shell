// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';

import '../../core/lock/app_lock_controller.dart';
import '../../core/lock/app_lock_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.lock});

  final AppLockController lock;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: lock,
        builder: (context, _) => ListView(
          children: [
            SwitchListTile(
              title: const Text('App lock'),
              subtitle: Text(
                lock.secureLockScreen
                    ? 'Ask for your fingerprint or screen lock when opening '
                          'the app and when coming back after a while.'
                    : 'Set a screen lock in Android settings to use app lock.',
              ),
              value: lock.enabled,
              onChanged: lock.setEnabled,
            ),
            ListTile(
              enabled: lock.enabled,
              title: const Text('Lock after'),
              trailing: DropdownButton<LockTimeout>(
                value: lock.timeout,
                onChanged: lock.enabled
                    ? (v) => v == null ? null : lock.setTimeout(v)
                    : null,
                items: [
                  for (final t in LockTimeout.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
