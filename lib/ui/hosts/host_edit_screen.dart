// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:math';

import '../theme.dart';

import 'package:flutter/material.dart';

import '../../core/hosts/host.dart';
import '../../core/hosts/host_repository.dart';
import '../../core/hosts/known_hosts.dart';
import '../../core/keys/key_service.dart';
import '../../core/keys/ssh_key.dart';
import '../private_input.dart';

/// Add or edit a host. When editing, also shows the trusted host key with a
/// button to remove it (the only way past a host key mismatch).
class HostEditScreen extends StatefulWidget {
  const HostEditScreen({
    super.key,
    required this.hosts,
    required this.knownHosts,
    required this.keyService,
    this.host,
  });

  final HostRepository hosts;
  final KnownHostsStore knownHosts;
  final KeyService keyService;
  final Host? host;

  @override
  State<HostEditScreen> createState() => _HostEditScreenState();
}

class _HostEditScreenState extends State<HostEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.host?.label);
  late final _hostname = TextEditingController(text: widget.host?.hostname);
  late final _port = TextEditingController(
    text: (widget.host?.port ?? 22).toString(),
  );
  late final _username = TextEditingController(text: widget.host?.username);
  HostKey? _trusted;
  late AuthMethod _auth = widget.host?.authMethod ?? AuthMethod.password;
  late String? _keyId = widget.host?.keyId;
  late bool _fallback = widget.host?.allowPasswordFallback ?? false;
  List<SshKey> _keys = const [];

  @override
  void initState() {
    super.initState();
    _loadTrusted();
    widget.keyService.list().then((keys) {
      if (mounted) setState(() => _keys = keys);
    });
  }

  Future<void> _loadTrusted() async {
    final h = widget.host;
    if (h == null) return;
    final key = await widget.knownHosts.get(h.hostname, h.port);
    if (mounted) setState(() => _trusted = key);
  }

  @override
  void dispose() {
    _label.dispose();
    _hostname.dispose();
    _port.dispose();
    _username.dispose();
    super.dispose();
  }

  static String _newId() {
    final r = Random.secure();
    return List.generate(
      8,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_auth == AuthMethod.key && _keyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a key, or log in with a password.'),
        ),
      );
      return;
    }
    final old = widget.host;
    final host = Host(
      id: old?.id ?? _newId(),
      label: _label.text.trim(),
      hostname: _hostname.text.trim(),
      port: int.parse(_port.text.trim()),
      username: _username.text.trim(),
      authMethod: _auth,
      keyId: _auth == AuthMethod.key ? _keyId : null,
      allowPasswordFallback: _auth == AuthMethod.key && _fallback,
    );
    await widget.hosts.upsert(host);
    // A trusted key belongs to hostname:port. If that changed, the old entry
    // would be orphaned, so drop it.
    if (old != null &&
        (KnownHostsStore.entryKey(old.hostname, old.port) !=
            KnownHostsStore.entryKey(host.hostname, host.port))) {
      await widget.knownHosts.remove(old.hostname, old.port);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _removeKey() async {
    final h = widget.host!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove trusted host key?'),
        content: const Text(
          'Only do this if you know why the server key changed, for example '
          'after a reinstall. The next connection will ask you to trust the '
          'key it presents.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: destructiveTextStyle(),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.knownHosts.remove(h.hostname, h.port);
    await _loadTrusted();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.host == null ? 'Add host' : 'Edit host'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PrivateTextFormField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label'),
              validator: _required,
              textInputAction: TextInputAction.next,
            ),
            PrivateTextFormField(
              controller: _hostname,
              decoration: const InputDecoration(
                labelText: 'Hostname',
                helperText: 'Name or address only, without user@',
              ),
              style: monoStyle,
              keyboardType: TextInputType.url,
              validator: (v) {
                if (_required(v) != null) return 'Required';
                if (RegExp(r'\s').hasMatch(v!.trim())) {
                  return 'No spaces allowed';
                }
                if (v.contains('@')) {
                  return 'Put the username in the Username field';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            PrivateTextFormField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'Port'),
              style: monoStyle,
              keyboardType: TextInputType.number,
              validator: (v) {
                final p = int.tryParse(v?.trim() ?? '');
                return (p == null || p < 1 || p > 65535)
                    ? 'Enter a port from 1 to 65535'
                    : null;
              },
              textInputAction: TextInputAction.next,
            ),
            PrivateTextFormField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Username'),
              style: monoStyle,
              validator: _required,
            ),
            const SizedBox(height: 24),
            Text('Login', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<AuthMethod>(
              segments: const [
                ButtonSegment(
                  value: AuthMethod.password,
                  label: Text('Password'),
                ),
                ButtonSegment(value: AuthMethod.key, label: Text('Key')),
              ],
              selected: {_auth},
              onSelectionChanged: (v) => setState(() => _auth = v.first),
            ),
            if (_auth == AuthMethod.key) ...[
              const SizedBox(height: 8),
              if (_keys.isEmpty)
                const Text(
                  'No keys yet. Create one under Keys on the host list.',
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _keys.any((k) => k.id == _keyId)
                      ? _keyId
                      : null,
                  decoration: const InputDecoration(labelText: 'Key'),
                  items: [
                    for (final k in _keys)
                      DropdownMenuItem(value: k.id, child: Text(k.name)),
                  ],
                  onChanged: (v) => setState(() => _keyId = v),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Also allow password if the server rejects the key',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                subtitle: Text(
                  'You are asked before a password is used. Off by default.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                value: _fallback,
                onChanged: (v) => setState(() => _fallback = v),
              ),
            ],
            if (widget.host != null) ...[
              const SizedBox(height: 32),
              Text(
                'Trusted host key',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_trusted == null)
                const Text('None yet. You will be asked on first connection.')
              else ...[
                Text(_trusted!.type, style: monoStyle),
                SelectableText(_trusted!.fingerprint, style: monoStyle),
                const SizedBox(height: 8),
                OutlinedButton(
                  style: destructiveOutlineStyle(),
                  onPressed: _removeKey,
                  child: const Text('Remove trusted key'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
