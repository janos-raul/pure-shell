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
import '../theme.dart';

/// What the sheet was closed with: a snippet to use, or a request to open the
/// manager.
sealed class SnippetSheetResult {
  const SnippetSheetResult();
}

class UseSnippet extends SnippetSheetResult {
  const UseSnippet(this.snippet);
  final Snippet snippet;
}

class ManageSnippets extends SnippetSheetResult {
  const ManageSnippets();
}

/// The session's snippet list: this host's snippets first, then the global
/// ones. Tap one to insert or run it. With [live] false (the session has
/// ended) the snippets are listed but cannot be used.
Future<SnippetSheetResult?> showSnippetSheet(
  BuildContext context, {
  required SnippetRepository snippets,
  required Host host,
  required bool live,
}) => showModalBottomSheet<SnippetSheetResult>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _SnippetSheet(snippets: snippets, host: host, live: live),
);

class _SnippetSheet extends StatelessWidget {
  const _SnippetSheet({
    required this.snippets,
    required this.host,
    required this.live,
  });

  final SnippetRepository snippets;
  final Host host;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: FutureBuilder<List<Snippet>>(
          future: snippets.forHost(host.id),
          builder: (context, snap) {
            final list = snap.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!live)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      key: const ValueKey('snippets-ended'),
                      'The session has ended, so snippets cannot be used.',
                      style: const TextStyle(color: errorRed),
                    ),
                  ),
                if (list == null)
                  const SizedBox(height: 48)
                else if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'No snippets yet. Save the commands you type often, '
                      'then insert or run them with one tap.',
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final s in list)
                          ListTile(
                            key: ValueKey('snippet-${s.id}'),
                            enabled: live,
                            leading: Icon(
                              s.mode == SnippetMode.run
                                  ? Icons.keyboard_return
                                  : Icons.edit_note,
                              color: live ? accentAmber : null,
                              semanticLabel: s.mode == SnippetMode.run
                                  ? 'Run'
                                  : 'Insert',
                            ),
                            title: Text(s.name),
                            subtitle: Text(
                              s.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: monoStyle,
                            ),
                            trailing: s.isGlobal
                                ? null
                                : const Tooltip(
                                    message: 'Only for this host',
                                    child: Icon(Icons.dns_outlined, size: 18),
                                  ),
                            onTap: live
                                ? () => Navigator.pop(context, UseSnippet(s))
                                : null,
                          ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                ListTile(
                  key: const ValueKey('snippets-manage'),
                  leading: const Icon(Icons.tune),
                  title: const Text('Manage snippets'),
                  onTap: () => Navigator.pop(context, const ManageSnippets()),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
