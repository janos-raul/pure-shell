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

import 'package:flutter/services.dart';

import '../../core/keys/key_service.dart';
import '../../core/keys/keystore_api.dart';
import '../../core/keys/ssh_key.dart';
import '../../core/platform_support.dart';
import 'keys_screen.dart' show helloKeyNotice;
import '../private_input.dart';
import '../help/help_content.dart';
import '../help/help_screen.dart';
import 'key_widgets.dart';
import 'share.dart';

class KeyDetailScreen extends StatefulWidget {
  const KeyDetailScreen({
    super.key,
    required this.keyService,
    required this.sshKey,
  });

  final KeyService keyService;
  final SshKey sshKey;

  @override
  State<KeyDetailScreen> createState() => _KeyDetailScreenState();
}

class _KeyDetailScreenState extends State<KeyDetailScreen> {
  late SshKey _key = widget.sshKey;
  late final _name = TextEditingController(text: _key.name);
  late final _comment = TextEditingController(text: _key.comment);
  SecurityLevel? _level;

  @override
  void initState() {
    super.initState();
    widget.keyService.displayLevel(_key).then((l) {
      if (mounted) setState(() => _level = l);
    });
    _name.addListener(_changed);
    _comment.addListener(_changed);
  }

  void _changed() => setState(() {});

  /// Save sits in the app bar (like Edit host) and only shows when there is
  /// something to save.
  bool get _dirty =>
      _name.text.trim().isNotEmpty &&
      (_name.text.trim() != _key.name || _comment.text != _key.comment);

  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await widget.keyService.rename(_key, name: name, comment: _comment.text);
    final updated = await widget.keyService.get(_key.id);
    if (updated != null && mounted) setState(() => _key = updated);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _key.authorizedKeysLine));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Public key copied')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${_key.name}"?'),
        content: const Text(
          'This cannot be undone. The private key cannot be recovered or '
          'exported, and servers that trust this key will no longer accept '
          'you until you create a new key and add it to them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: destructiveTextStyle(),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete key'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.keyService.delete(_key);
      if (mounted) Navigator.of(context).pop();
    } on KeystoreException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = _key.authorizedKeysLine;
    return Scaffold(
      appBar: AppBar(
        title: Text(_key.name),
        actions: [
          if (_dirty) TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              SecurityBadge(sshKey: _key, level: _level),
              const SizedBox(width: 12),
              Text(_key.sshType),
            ],
          ),
          if (_key.kind == KeyKind.helloRsa)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(helloKeyNotice),
            ),
          if (_key.isSoftware)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                windowsStub
                    ? 'EXPERIMENTAL Windows build: software key, not in a TPM, '
                          'no confirmation on use.'
                    : 'This phone reports no secure hardware for keys, so this '
                          'is a software key.',
              ),
            ),
          const SizedBox(height: 16),
          PrivateTextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          PrivateTextFormField(
            controller: _comment,
            decoration: const InputDecoration(labelText: 'Comment'),
          ),
          const SizedBox(height: 16),
          Text(
            'Public key (authorized_keys line)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          SelectableText(line, style: monoStyle.copyWith(fontSize: 12)),
          const SizedBox(height: 8),
          Text(_key.fingerprint, style: monoStyle.copyWith(fontSize: 12)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: linkButtonStyle(),
              onPressed: () => openHelpTopic(context, helpAddKey),
              child: const Text('How to add this key to a server'),
            ),
          ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => shareText(line),
                icon: const Icon(Icons.share),
                label: const Text('Share'),
              ),
            ],
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            style: destructiveOutlineStyle(),
            onPressed: _delete,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Delete key'),
          ),
        ],
      ),
    );
  }
}
