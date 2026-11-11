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
import '../../core/platform_support.dart';
import '../about_screen.dart';
import '../../core/lock/app_lock_settings.dart';
import '../../core/ssh/session_keeper.dart';
import '../../core/storage/screenshot_settings.dart';
import '../../core/storage/terminal_settings.dart';
import '../theme.dart';

/// One choice in a [showChoiceDialog]: its name and a one-line explanation.
class ChoiceOption<T> {
  const ChoiceOption(this.value, this.label, this.description);

  final T value;
  final String label;
  final String description;
}

/// The Android settings pattern: a dialog listing the options, each with a
/// one-line explanation, the current one ticked. Returns the chosen value, or
/// null if dismissed.
Future<T?> showChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required T current,
  required List<ChoiceOption<T>> options,
}) {
  return showDialog<T>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(title),
      children: [
        for (final o in options)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            title: Text(o.label),
            subtitle: Text(o.description),
            trailing: o.value == current ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(c, o.value),
          ),
      ],
    ),
  );
}

class SettingsScreen extends StatefulWidget {
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
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  var _inputMode = InputMode.direct;
  var _colors = TerminalColors.standard;
  var _keepSessions = true;
  var _showExtraKeys = false;

  @override
  void initState() {
    super.initState();
    widget.terminal.loadShowExtraKeys().then((v) {
      if (mounted) setState(() => _showExtraKeys = v);
    });
    widget.terminal.loadKeepSessions().then((v) {
      if (mounted) setState(() => _keepSessions = v);
    });
    widget.terminal.loadInputMode().then((m) {
      if (mounted) setState(() => _inputMode = m);
    });
    widget.terminal.loadColors().then((c) {
      if (mounted) setState(() => _colors = c);
    });
  }

  static String _timeoutHelp(LockTimeout t) =>
      windowsStub ? _desktopTimeoutHelp(t) : _phoneTimeoutHelp(t);

  /// Locking Windows (Win+L) always locks at once; this is for minimising.
  static String _desktopTimeoutHelp(LockTimeout t) => switch (t) {
    LockTimeout.immediately => 'Locks as soon as the window is minimised.',
    LockTimeout.oneMinute =>
      'Stays unlocked if you restore the window within a minute.',
    LockTimeout.fiveMinutes =>
      'Stays unlocked if you restore the window within 5 minutes.',
    LockTimeout.fifteenMinutes =>
      'Stays unlocked if you restore the window within 15 minutes.',
  };

  static String _phoneTimeoutHelp(LockTimeout t) => switch (t) {
    LockTimeout.immediately => 'Locks as soon as you leave the app.',
    LockTimeout.oneMinute => 'Stays unlocked if you are back within a minute.',
    LockTimeout.fiveMinutes =>
      'Stays unlocked if you are back within 5 minutes.',
    LockTimeout.fifteenMinutes =>
      'Stays unlocked if you are back within 15 minutes.',
  };

  Future<void> _chooseAppLock() async {
    final lock = widget.lock;
    final chosen = await showChoiceDialog<bool>(
      context,
      title: 'App lock',
      current: lock.enabled,
      options: windowsStub
          ? [
              ChoiceOption(
                true,
                'On',
                lock.secureLockScreen
                    ? 'Locks when Windows locks and when the window stays '
                          'minimised; Windows Hello unlocks it. Sessions keep '
                          'running while it is locked.'
                    : lock.unavailableReason == 'remote'
                    ? 'Windows Hello cannot be used over Remote Desktop, so '
                          'the lock only works at the computer itself.'
                    : 'Needs Windows Hello: set up a PIN, fingerprint or face '
                          'in Windows Settings, Accounts, Sign-in options.',
              ),
              const ChoiceOption(
                false,
                'Off',
                'Anyone who uses this Windows account can open the app.',
              ),
            ]
          : [
              ChoiceOption(
                true,
                'On',
                lock.secureLockScreen
                    ? 'Ask for your fingerprint or screen lock to open the app.'
                    : 'Needs a screen lock: set one in Android settings.',
              ),
              const ChoiceOption(
                false,
                'Off',
                'Anyone who opens the phone can open the app.',
              ),
            ],
    );
    if (chosen != null) await lock.setEnabled(chosen);
  }

  Future<void> _chooseTimeout() async {
    final lock = widget.lock;
    final chosen = await showChoiceDialog<LockTimeout>(
      context,
      title: 'Lock after',
      current: lock.timeout,
      options: [
        for (final t in LockTimeout.values)
          ChoiceOption(t, t.label, _timeoutHelp(t)),
      ],
    );
    if (chosen != null) await lock.setTimeout(chosen);
  }

  Future<void> _chooseScreenshots() async {
    final chosen = await showChoiceDialog<bool>(
      context,
      title: 'Allow screenshots',
      current: widget.screenshots.allowed,
      options: [
        ChoiceOption(
          false,
          'Off',
          windowsStub
              ? 'Leaves this window out of screenshots, screen recording and '
                    'screen sharing.'
              : 'Blocks screenshots, screen recording and the recent-apps '
                    'preview.',
        ),
        const ChoiceOption(
          true,
          'On',
          'Allows them; they can capture hostnames, usernames and output.',
        ),
      ],
    );
    if (chosen != null) await widget.screenshots.setAllowed(chosen);
  }

  Future<void> _chooseKeepSessions() async {
    final chosen = await showChoiceDialog<bool>(
      context,
      title: 'Keep sessions alive',
      current: _keepSessions,
      options: const [
        ChoiceOption(
          true,
          'On',
          'Shows a notification with the number of sessions (nothing else) '
              'while you are connected, so Android does not cut the '
              'connections a few seconds after you leave the app.',
        ),
        ChoiceOption(
          false,
          'Off',
          'No notification. Android ends your sessions shortly after you '
              'leave the app.',
        ),
      ],
    );
    if (chosen == null) return;
    setState(() => _keepSessions = chosen);
    await widget.terminal.saveKeepSessions(chosen);
    await SessionKeeper.instance.setEnabled(chosen);
  }

  Future<void> _chooseInputMode() async {
    final chosen = await showChoiceDialog<InputMode>(
      context,
      title: 'Input mode',
      current: _inputMode,
      options: [
        for (final m in InputMode.values)
          ChoiceOption(m, m.label, m.description),
      ],
    );
    if (chosen == null) return;
    setState(() => _inputMode = chosen);
    await widget.terminal.saveInputMode(chosen);
  }

  Future<void> _chooseExtraKeys() async {
    final chosen = await showChoiceDialog<bool>(
      context,
      title: 'Extra keys row',
      current: _showExtraKeys,
      options: const [
        ChoiceOption(
          false,
          'Off',
          'Use the keyboard: Esc, Tab, Ctrl and the arrows are all there.',
        ),
        ChoiceOption(
          true,
          'On',
          'Shows Esc, Tab, Ctrl, arrows, Paste and the command box under the '
              'terminal.',
        ),
      ],
    );
    if (chosen == null) return;
    setState(() => _showExtraKeys = chosen);
    await widget.terminal.saveShowExtraKeys(chosen);
  }

  Future<void> _chooseColors() async {
    final chosen = await showChoiceDialog<TerminalColors>(
      context,
      title: 'Terminal colors',
      current: _colors,
      options: [
        for (final c in TerminalColors.values)
          ChoiceOption(c, c.label, c.description),
      ],
    );
    if (chosen == null) return;
    setState(() => _colors = chosen);
    await widget.terminal.saveColors(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.lock, widget.screenshots]),
        builder: (context, _) {
          final lock = widget.lock;
          return ListView(
            children: [
              const _Section('Security'),
              _Box([
                ListTile(
                  title: const Text('App lock'),
                  subtitle: Text(
                    !lock.enabled
                        ? 'Off'
                        : lock.secureLockScreen
                        ? 'On'
                        : lock.unavailableReason == 'remote'
                        ? 'Not available in a Remote Desktop session'
                        : windowsStub
                        ? 'Not available: Windows Hello is not set up'
                        : 'On, but the phone has no screen lock',
                  ),
                  onTap: _chooseAppLock,
                ),
                ListTile(
                  enabled: lock.enabled,
                  title: Text(
                    windowsStub ? 'Lock when minimised for' : 'Lock after',
                  ),
                  subtitle: Text(lock.timeout.label),
                  onTap: lock.enabled ? _chooseTimeout : null,
                ),
                ListTile(
                  title: const Text('Allow screenshots'),
                  subtitle: Text(widget.screenshots.allowed ? 'On' : 'Off'),
                  onTap: _chooseScreenshots,
                ),
              ]),
              if (!windowsStub) const _Section('Connection'),
              if (!windowsStub)
                _Box([
                  ListTile(
                    title: const Text('Keep sessions alive'),
                    subtitle: Text(_keepSessions ? 'On' : 'Off'),
                    onTap: _chooseKeepSessions,
                  ),
                ]),
              const _Section('Terminal'),
              _Box([
                // Soft-keyboard modes; the desktop always uses text input.
                if (!windowsStub)
                  ListTile(
                    title: const Text('Input mode'),
                    subtitle: Text(_inputMode.label),
                    onTap: _chooseInputMode,
                  ),
                if (windowsStub)
                  ListTile(
                    title: const Text('Extra keys row'),
                    subtitle: Text(_showExtraKeys ? 'On' : 'Off'),
                    onTap: _chooseExtraKeys,
                  ),
                ListTile(
                  title: const Text('Terminal colors'),
                  subtitle: Text(_colors.label),
                  onTap: _chooseColors,
                ),
              ]),
              const _Section('About'),
              _Box([
                ListTile(
                  title: const Text('About Pure-Shell'),
                  subtitle: const Text('Version, license and source code'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  ),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: emphasisBlue, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// The settings of one section in a square box with a thin outline; the rows
/// are separated by a hairline.
class _Box extends StatelessWidget {
  const _Box(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outline;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      decoration: BoxDecoration(border: Border.all(color: line)),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: line),
            children[i],
          ],
        ],
      ),
    );
  }
}
