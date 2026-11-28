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
import 'snippet_edit_screen.dart';

/// Add, edit, delete and reorder snippets. With a [host], two lists: that
/// host's snippets and the global ones. Without, only the global list.
class SnippetsScreen extends StatefulWidget {
  const SnippetsScreen({super.key, required this.snippets, this.host});

  final SnippetRepository snippets;
  final Host? host;

  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
  List<Snippet>? _hostList;
  List<Snippet>? _globalList;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final host = widget.host;
    final hostList = host == null
        ? <Snippet>[]
        : await widget.snippets.inScope(host.id);
    final globalList = await widget.snippets.inScope(null);
    if (!mounted) return;
    setState(() {
      _hostList = hostList;
      _globalList = globalList;
    });
  }

  Future<void> _edit([Snippet? snippet]) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SnippetEditScreen(
          snippets: widget.snippets,
          host: widget.host,
          snippet: snippet,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _delete(Snippet snippet) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${snippet.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.snippets.delete(snippet);
    await _reload();
  }

  /// [newIndex] is the final position (ReorderableListView.onReorderItem);
  /// the repository takes the position before the removal.
  Future<void> _reorder(String? hostId, int oldIndex, int newIndex) async {
    // Show the new order at once; the store follows.
    final list = hostId == null ? _globalList! : _hostList!;
    list.insert(newIndex, list.removeAt(oldIndex));
    setState(() {});
    await widget.snippets.reorder(
      hostId,
      oldIndex,
      newIndex > oldIndex ? newIndex + 1 : newIndex,
    );
  }

  Widget _group(String title, String? hostId, List<Snippet> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('None yet'),
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (o, n) => _reorder(hostId, o, n),
            children: [
              for (var i = 0; i < list.length; i++)
                ListTile(
                  key: ValueKey(list[i].id),
                  leading: Icon(
                    list[i].mode == SnippetMode.run
                        ? Icons.keyboard_return
                        : Icons.edit_note,
                    color: accentAmber,
                    semanticLabel: list[i].mode == SnippetMode.run
                        ? 'Run'
                        : 'Insert',
                  ),
                  title: Text(list[i].name),
                  subtitle: Text(
                    list[i].text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle,
                  ),
                  onTap: () => _edit(list[i]),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        onSelected: (v) =>
                            v == 'edit' ? _edit(list[i]) : _delete(list[i]),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Tooltip(
                          message: 'Drag to reorder',
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final hostList = _hostList;
    final globalList = _globalList;
    return Scaffold(
      appBar: AppBar(title: const Text('Snippets')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        tooltip: 'Add snippet',
        child: const Icon(Icons.add),
      ),
      body: (hostList == null || globalList == null)
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                if (host != null)
                  _group('For ${host.label}', host.id, hostList),
                _group('For every host', null, globalList),
              ],
            ),
    );
  }
}
