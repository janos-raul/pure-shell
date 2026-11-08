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
import '../../core/storage/screenshot_settings.dart';
import '../../core/storage/terminal_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.lock,
    required this.screenshots,
    required this.terminal,
  });

  final AppLockController lock;
  final ScreenshotSettings screenshots;
  final TerminalSettings terminal;

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
            _InputModeTile(settings: terminal),
            _TerminalColorsTile(settings: terminal),
            ListenableBuilder(
              listenable: screenshots,
              builder: (context, _) => SwitchListTile(
                title: const Text('Allow screenshots'),
                subtitle: const Text(
                  'Off: screenshots, screen recording and the recent-apps '
                  'preview are blocked. On: they work, and may capture '
                  'hostnames, usernames and terminal output.',
                ),
                value: screenshots.allowed,
                onChanged: screenshots.setAllowed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalColorsTile extends StatefulWidget {
  const _TerminalColorsTile({required this.settings});

  final TerminalSettings settings;

  @override
  State<_TerminalColorsTile> createState() => _TerminalColorsTileState();
}

class _TerminalColorsTileState extends State<_TerminalColorsTile> {
  var _colors = TerminalColors.standard;

  @override
  void initState() {
    super.initState();
    widget.settings.loadColors().then((c) {
      if (mounted) setState(() => _colors = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Terminal colors'),
      subtitle: Text(_colors.description),
      trailing: DropdownButton<TerminalColors>(
        value: _colors,
        onChanged: (c) {
          if (c == null) return;
          setState(() => _colors = c);
          widget.settings.saveColors(c);
        },
        items: [
          for (final c in TerminalColors.values)
            DropdownMenuItem(value: c, child: Text(c.label)),
        ],
      ),
    );
  }
}

class _InputModeTile extends StatefulWidget {
  const _InputModeTile({required this.settings});

  final TerminalSettings settings;

  @override
  State<_InputModeTile> createState() => _InputModeTileState();
}

class _InputModeTileState extends State<_InputModeTile> {
  var _mode = InputMode.direct;

  @override
  void initState() {
    super.initState();
    widget.settings.loadInputMode().then((m) {
      if (mounted) setState(() => _mode = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Input mode'),
      subtitle: Text(_mode.description),
      trailing: DropdownButton<InputMode>(
        value: _mode,
        onChanged: (m) {
          if (m == null) return;
          setState(() => _mode = m);
          widget.settings.saveInputMode(m);
        },
        items: [
          for (final m in InputMode.values)
            DropdownMenuItem(value: m, child: Text(m.label)),
        ],
      ),
    );
  }
}
