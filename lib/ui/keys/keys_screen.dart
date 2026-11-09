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

import '../../core/keys/key_service.dart';
import '../../core/keys/keystore_api.dart';
import '../../core/keys/ssh_ec_encoding.dart';
import '../../core/keys/ssh_key.dart';
import '../private_input.dart';
import 'key_detail_screen.dart';
import 'key_widgets.dart';

/// Shown once, before the first key is created (and mirrored in the README).
const keyLossNotice =
    'Keys are destroyed if you uninstall PureShell, clear its data, or '
    'reinstall it signed with a different key (for example a build from '
    'another source). They are not backed up and cannot be recovered or '
    'exported. Keep another way into your servers, such as a password or a '
    'second key.';

class KeysScreen extends StatefulWidget {
  const KeysScreen({super.key, required this.keyService});

  final KeyService keyService;

  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  List<SshKey>? _keys;
  final _levels = <String, SecurityLevel>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final keys = await widget.keyService.list();
    // Stored level, replaced by the live one where the two disagree.
    final levels = {
      for (final k in keys) k.id: await widget.keyService.displayLevel(k),
    };
    if (!mounted) return;
    setState(() {
      _keys = keys;
      _levels
        ..clear()
        ..addAll(levels);
    });
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _generate() async {
    final caps = await widget.keyService.capabilities();
    if (!mounted) return;
    if (!caps.secureLockScreen) {
      // Say what is wrong instead of surfacing a Keystore error.
      _snack(const KeystoreException(KeystoreErrorKind.noScreenLock).message);
      return;
    }
    if (!await widget.keyService.lossNoticeShown()) {
      if (!mounted) return;
      final understood = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Keys can be lost'),
          content: const Text(keyLossNotice),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('I understand'),
            ),
          ],
        ),
      );
      if (understood != true) return; // not acknowledged: ask again next time
      await widget.keyService.markLossNoticeShown();
    }
    if (!mounted) return;
    final result = await showDialog<({String name, String comment})>(
      context: context,
      builder: (_) => const _NewKeyDialog(),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final key = await widget.keyService.generate(
        name: result.name,
        comment: result.comment,
      );
      await _reload();
      if (!mounted) return;
      setState(
        () => _busy = false,
      ); // before any dialog, so nothing spins behind it
      if (key.isSoftware) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Software key'),
            content: const Text(
              'This phone reports no secure hardware for keys, so this key is '
              'a software key: it is protected by the Keystore and your '
              'fingerprint or screen lock, but not by secure hardware.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } on KeystoreException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = _keys;
    return Scaffold(
      appBar: AppBar(title: const Text('Keys')),
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : _generate,
        tooltip: 'Create key',
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(),
              )
            : const Icon(Icons.add),
      ),
      body: keys == null
          ? const SizedBox.shrink()
          : keys.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No keys yet. Tap + to create one. The private key is '
                  'made in your phone\'s secure hardware where available '
                  'and can never be exported.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final k in keys)
                  ListTile(
                    title: Text(k.name),
                    subtitle: Text(k.fingerprint, style: monoStyle),
                    trailing: SecurityBadge(sshKey: k, level: _levels[k.id]),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => KeyDetailScreen(
                            keyService: widget.keyService,
                            sshKey: k,
                          ),
                        ),
                      );
                      await _reload();
                    },
                  ),
              ],
            ),
    );
  }
}

class _NewKeyDialog extends StatefulWidget {
  const _NewKeyDialog();

  @override
  State<_NewKeyDialog> createState() => _NewKeyDialogState();
}

class _NewKeyDialogState extends State<_NewKeyDialog> {
  final _name = TextEditingController();
  final _comment = TextEditingController(text: defaultKeyComment);
  final _form = GlobalKey<FormState>();

  /// "Required" is only shown after Create was tapped with an empty name;
  /// from then on it follows what is typed.
  var _triedCreate = false;

  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create key'),
      content: Form(
        key: _form,
        autovalidateMode: _triedCreate
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrivateTextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText: 'Only shown on this phone',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            PrivateTextFormField(
              controller: _comment,
              decoration: const InputDecoration(
                labelText: 'Comment (shown on servers)',
                helperText: 'Nothing personal is added unless you type it.',
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            setState(() => _triedCreate = true);
            if (_form.currentState!.validate()) {
              Navigator.pop(context, (
                name: _name.text.trim(),
                comment: _comment.text,
              ));
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
