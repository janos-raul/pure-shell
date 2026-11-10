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

import '../../core/hosts/host.dart';
import '../../core/hosts/host_repository.dart';
import '../../core/hosts/known_hosts.dart';
import '../../core/storage/screenshot_settings.dart';
import '../../core/storage/terminal_settings.dart';
import '../../core/keys/key_service.dart';
import '../../core/lock/app_lock_controller.dart';
import '../about_screen.dart';
import '../help/help_screen.dart';
import '../keys/keys_screen.dart';
import '../settings/settings_screen.dart';
import 'connect_flow.dart';
import 'host_edit_screen.dart';
import 'welcome_view.dart';

class HostListScreen extends StatefulWidget {
  const HostListScreen({
    super.key,
    required this.hosts,
    required this.knownHosts,
    required this.settings,
    required this.keyService,
    required this.lock,
    required this.screenshots,
  });

  final HostRepository hosts;
  final KnownHostsStore knownHosts;
  final TerminalSettings settings;
  final KeyService keyService;
  final AppLockController lock;
  final ScreenshotSettings screenshots;

  @override
  State<HostListScreen> createState() => _HostListScreenState();
}

class _HostListScreenState extends State<HostListScreen> {
  List<Host>? _hosts;
  var _hasKeys = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.hosts.list();
    final keys = await widget.keyService.list();
    if (mounted) {
      setState(() {
        _hosts = list;
        _hasKeys = keys.isNotEmpty;
      });
    }
  }

  Future<void> _edit([Host? host]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => HostEditScreen(
          hosts: widget.hosts,
          knownHosts: widget.knownHosts,
          keyService: widget.keyService,
          host: host,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _openMenuItem(String item) async {
    final Widget page = switch (item) {
      'keys' => KeysScreen(keyService: widget.keyService),
      'help' => const HelpScreen(),
      'about' => const AboutScreen(),
      _ => SettingsScreen(
        lock: widget.lock,
        screenshots: widget.screenshots,
        terminal: widget.settings,
      ),
    };
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    await _reload(); // a key may have been made or deleted
  }

  Future<void> _createKey() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            KeysScreen(keyService: widget.keyService, startCreating: true),
      ),
    );
    await _reload();
  }

  Future<void> _delete(Host host) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${host.label}"?'),
        content: const Text('The host and its trusted host key are removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: destructiveTextStyle(),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.hosts.delete(host);
    await _reload();
  }

  Future<void> _connect(Host host) => connectToHost(
    context,
    host: host,
    knownHosts: widget.knownHosts,
    settings: widget.settings,
    keyService: widget.keyService,
  );

  @override
  Widget build(BuildContext context) {
    final hosts = _hosts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pure-Shell'),
        // One menu instead of icons: the key icon in the bar looked like the
        // per-host key icon in the list.
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: _openMenuItem,
            itemBuilder: (_) => [
              _menuItem('keys', 'Keys', Icons.vpn_key_outlined),
              _menuItem('settings', 'Settings', Icons.settings_outlined),
              _menuItem('help', 'Help', Icons.help_outline),
              _menuItem('about', 'About', Icons.info_outline),
            ],
          ),
        ],
      ),
      // Not while the welcome is shown: its "Add a host" is the same action.
      floatingActionButton: (hosts == null || hosts.isEmpty)
          ? null
          : FloatingActionButton(
              onPressed: () => _edit(),
              tooltip: 'Add host',
              child: const Icon(Icons.add),
            ),
      body: hosts == null
          ? const SizedBox.shrink()
          : hosts.isEmpty
          ? WelcomeView(
              hasKeys: _hasKeys,
              onAddHost: () => _edit(),
              onCreateKey: _createKey,
              onHelp: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
              ),
            )
          : ListView.builder(
              itemCount: hosts.length,
              itemBuilder: (context, i) {
                final h = hosts[i];
                final byKey = h.authMethod == AuthMethod.key;
                return ListTile(
                  leading: Tooltip(
                    message: byKey ? 'Key login' : 'Password login',
                    // A matching pair, same size and weight.
                    child: Icon(
                      byKey ? Icons.vpn_key_outlined : Icons.lock_outline,
                      color: accentAmber,
                      semanticLabel: byKey ? 'Key login' : 'Password login',
                    ),
                  ),
                  // Proportional (the app font); only the address is mono.
                  title: Text(h.label),
                  subtitle: Text(
                    '${h.username}@${h.hostname}${h.port == 22 ? '' : ':${h.port}'}',
                    style: monoStyle,
                  ),
                  onTap: () => _connect(h),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? _edit(h) : _delete(h),
                    itemBuilder: (_) => [
                      _menuItem('edit', 'Edit', Icons.edit_outlined),
                      _menuItem(
                        'delete',
                        'Delete',
                        Icons.delete_outline,
                        destructive: true,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// A menu entry with a small leading icon.
PopupMenuItem<String> _menuItem(
  String value,
  String label,
  IconData icon, {
  bool destructive = false,
}) => PopupMenuItem<String>(
  value: value,
  child: Row(
    children: [
      Icon(icon, size: 20, color: destructive ? errorRed : menuIconColor),
      const SizedBox(width: 12),
      Text(label, style: destructive ? const TextStyle(color: errorRed) : null),
    ],
  ),
);
