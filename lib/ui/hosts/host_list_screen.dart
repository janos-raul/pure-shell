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
import '../keys/keys_screen.dart';
import '../settings/settings_screen.dart';
import 'connect_flow.dart';
import 'host_edit_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.hosts.list();
    if (mounted) setState(() => _hosts = list);
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
        title: const Text('PureShell'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(
                  lock: widget.lock,
                  screenshots: widget.screenshots,
                  terminal: widget.settings,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.vpn_key),
            tooltip: 'Keys',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => KeysScreen(keyService: widget.keyService),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        tooltip: 'Add host',
        child: const Icon(Icons.add),
      ),
      body: hosts == null
          ? const SizedBox.shrink()
          : hosts.isEmpty
          ? const Center(child: Text('No hosts yet. Tap + to add one.'))
          : ListView.builder(
              itemCount: hosts.length,
              itemBuilder: (context, i) {
                final h = hosts[i];
                return ListTile(
                  title: Text(h.label),
                  subtitle: Text(
                    '${h.username}@${h.hostname}${h.port == 22 ? '' : ':${h.port}'}',
                    style: monoStyle,
                  ),
                  onTap: () => _connect(h),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? _edit(h) : _delete(h),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
