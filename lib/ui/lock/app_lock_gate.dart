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

/// Puts the lock screen over the whole app (dialogs included) and feeds the
/// controller with lifecycle events.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.controller,
    required this.navigatorKey,
    required this.child,
  });

  final AppLockController controller;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  var _autoPromptDone = false;

  AppLockController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _c.handleLifecycle(state);

  /// The back button must not reveal what is under the lock screen.
  @override
  Future<bool> didPopRoute() async => _c.locked;

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (!_c.locked) {
      _autoPromptDone = false;
    } else if (!_c.hidden || !_autoPromptDone) {
      // Ask right away when the lock appears; if the user dismisses the
      // prompt they get the Unlock button instead of a nag loop.
      if (!_autoPromptDone && !_c.unlocking) {
        _autoPromptDone = true;
        _c.unlock();
      }
    }
    if (_c.noticePending && !_c.locked) _showNotice();
  }

  var _noticeShowing = false;

  Future<void> _showNotice() async {
    if (_noticeShowing) return;
    final context = widget.navigatorKey.currentContext;
    if (context == null) return;
    _noticeShowing = true;
    await _c.noticeShown(); // once: never repeated, even if dismissed
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('App lock needs a screen lock'),
        content: const Text(
          'PureShell cannot lock itself because this phone has no screen lock. '
          'Set a PIN, pattern, password or fingerprint in Android settings to '
          'protect the app (and to create keys).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    _noticeShowing = false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_c.hidden)
          Positioned.fill(
            child: _LockScreen(
              locked: _c.locked,
              busy: _c.unlocking,
              onUnlock: _c.unlock,
            ),
          ),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.locked,
    required this.busy,
    required this.onUnlock,
  });

  final bool locked;
  final bool busy;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0F1115),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 64, color: Color(0xFF4ADE80)),
              const SizedBox(height: 16),
              if (locked) ...[
                const Text(
                  'PureShell is locked',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : onUnlock,
                  child: const Text('Unlock'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
