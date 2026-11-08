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
import '../../core/hosts/host_repository.dart';
import '../../core/hosts/known_hosts.dart';
import '../../core/ssh/connect_result.dart';
import '../../core/ssh/ssh_connection.dart';
import '../terminal/terminal_screen.dart';
import 'host_edit_screen.dart';
import 'host_key_mismatch_screen.dart';

class HostListScreen extends StatefulWidget {
  const HostListScreen({
    super.key,
    required this.hosts,
    required this.knownHosts,
  });

  final HostRepository hosts;
  final KnownHostsStore knownHosts;

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

  Future<String?> _askPassword(Host host) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${host.username}@${host.hostname}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<bool> _askTrust(Host host, HostKey key) async {
    final trusted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('New host key'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('First connection to ${host.hostname}:${host.port}.'),
              const SizedBox(height: 12),
              const Text(
                'Key type',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(key.type),
              const SizedBox(height: 8),
              const Text(
                'SHA-256 fingerprint',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(
                key.fingerprint,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Compare it with the fingerprint from your server '
                '(ssh-keygen -lf). The server drops the connection after '
                'about two minutes of waiting.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Trust'),
          ),
        ],
      ),
    );
    return trusted == true;
  }

  Future<void> _connect(Host host) async {
    final password = await _askPassword(host);
    if (password == null || !mounted) return;

    final conn = SshConnection(
      host: host,
      knownHosts: widget.knownHosts,
      onTrustPrompt: (key) => _askTrust(host, key),
    );

    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Connecting...'),
            ],
          ),
        ),
      ),
    );
    final outcome = await conn.connect(password);
    if (!mounted) {
      conn.close();
      return;
    }
    navigator.pop(); // progress dialog

    switch (outcome.result) {
      case ConnectResult.trusted:
      case ConnectResult.firstUseAccepted:
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => TerminalScreen(host: host, connection: conn),
          ),
        );
      case ConnectResult.mismatch:
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => HostKeyMismatchScreen(
              host: host,
              stored: outcome.storedKey,
              presented: outcome.presentedKey,
            ),
          ),
        );
      case ConnectResult.firstUseDeclined:
        _snack('Host key not trusted. Connection cancelled.');
      case ConnectResult.otherError:
        _snack(
          connectFailureMessage(outcome.failure ?? ConnectFailure.unknown),
        );
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final hosts = _hosts;
    return Scaffold(
      appBar: AppBar(title: const Text('PureShell')),
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
