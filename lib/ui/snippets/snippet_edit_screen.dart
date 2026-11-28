// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:material_ui/material_ui.dart';

import '../../core/hosts/host.dart';
import '../../core/snippets/snippet.dart';
import '../../core/snippets/snippet_repository.dart';
import '../private_input.dart';
import '../theme.dart';

/// Add or edit one snippet. [host] is the host the manager was opened for:
/// with it the snippet can be tied to that host or global; without it the
/// snippet is global.
class SnippetEditScreen extends StatefulWidget {
  const SnippetEditScreen({
    super.key,
    required this.snippets,
    this.host,
    this.snippet,
  });

  final SnippetRepository snippets;
  final Host? host;

  /// The snippet being edited; null adds a new one.
  final Snippet? snippet;

  @override
  State<SnippetEditScreen> createState() => _SnippetEditScreenState();
}

class _SnippetEditScreenState extends State<SnippetEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.snippet?.name);
  late final _text = TextEditingController(text: widget.snippet?.text);
  late SnippetMode _mode = widget.snippet?.mode ?? SnippetMode.insert;
  late bool _confirm = widget.snippet?.confirm ?? false;
  late bool _hostOnly =
      widget.snippet?.hostId != null ||
      (widget.snippet == null && widget.host != null);

  /// Until the user touches the switch, it follows the text: on for several
  /// lines, off for one.
  late bool _confirmTouched = widget.snippet != null;

  @override
  void initState() {
    super.initState();
    _text.addListener(_followText);
  }

  void _followText() {
    if (_confirmTouched) return;
    final want = Snippet.confirmDefaultFor(_text.text);
    if (want != _confirm) setState(() => _confirm = want);
  }

  @override
  void dispose() {
    _text.removeListener(_followText);
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.snippet;
    final hostId = _hostOnly ? (widget.host?.id ?? old?.hostId) : null;
    // Line breaks as plain \n, none at the end (a snippet is not "ls\n").
    final text = _text.text
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\n+$'), '');
    await widget.snippets.upsert(
      Snippet(
        id: old?.id ?? Snippet.newId(),
        name: _name.text.trim(),
        text: text,
        hostId: hostId,
        mode: _mode,
        confirm: _confirm,
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final canTie = host != null || widget.snippet?.hostId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.snippet == null ? 'Add snippet' : 'Edit snippet'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              key: const ValueKey('snippet-secrets-note'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: accentAmber),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "Don't put passwords or other secrets in snippets. They are "
                'plain text in the app, and a run snippet sends them to the '
                'server as typed.',
              ),
            ),
            const SizedBox(height: 12),
            PrivateTextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: _required,
              textInputAction: TextInputAction.next,
            ),
            PrivateTextFormField(
              controller: _text,
              decoration: const InputDecoration(
                labelText: 'Command',
                helperText: 'One or several lines',
                alignLabelWithHint: true,
              ),
              style: monoStyle,
              minLines: 3,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              validator: _required,
            ),
            const SizedBox(height: 12),
            if (canTie)
              SwitchListTile(
                key: const ValueKey('snippet-host-only'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Only for this host'),
                subtitle: Text(
                  _hostOnly
                      ? 'Shown for ${host?.label ?? 'this host'} only'
                      : 'Shown for every host',
                ),
                value: _hostOnly,
                onChanged: (v) => setState(() => _hostOnly = v),
              ),
            const SizedBox(height: 4),
            const Text('When tapped'),
            const SizedBox(height: 8),
            SegmentedButton<SnippetMode>(
              key: const ValueKey('snippet-mode'),
              segments: const [
                ButtonSegment(
                  value: SnippetMode.insert,
                  label: Text('Insert'),
                  icon: Icon(Icons.edit_note),
                ),
                ButtonSegment(
                  value: SnippetMode.run,
                  label: Text('Run'),
                  icon: Icon(Icons.keyboard_return),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _mode == SnippetMode.insert
                    ? 'Puts the text in the command box, so you can change it '
                          'and send it yourself.'
                    : 'Sends the text and presses Enter. Several lines are '
                          'sent as one paste.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (_mode == SnippetMode.run)
              SwitchListTile(
                key: const ValueKey('snippet-confirm'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Ask before running'),
                subtitle: const Text('Shows the text and asks first'),
                value: _confirm,
                onChanged: (v) => setState(() {
                  _confirm = v;
                  _confirmTouched = true;
                }),
              ),
          ],
        ),
      ),
    );
  }
}
