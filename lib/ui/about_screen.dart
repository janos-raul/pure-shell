// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_info.dart';
import 'theme.dart';

/// Where the source lives. The links are shown as text you can copy: Pure-Shell
/// opens no browser and makes no network request of its own.
const sourceUrl = 'https://github.com/janos-raul/pure-shell';
const xtermForkDocUrl = '$sourceUrl/blob/main/docs/xterm-fork.md';
const xtermForkUrl = 'https://github.com/janos-raul/xterm.dart';
const copyrightLine = 'Copyright (C) 2026 Janos-Raul';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, this.appInfo});

  /// Where the version comes from (replaced in tests).
  final AppInfo? appInfo;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  AppVersion? _version;

  @override
  void initState() {
    super.initState();
    (widget.appInfo ?? AppInfo()).version().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About Pure-Shell')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Pure-Shell', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            _version?.toString() ?? 'Version unknown',
            style: monoStyle,
            key: const ValueKey('about-version'),
          ),
          const SizedBox(height: 12),
          const Text('An open-source SSH client for Android.'),
          const _Heading('License'),
          const Text(
            'GNU General Public License, version 3 or later. Pure-Shell comes '
            'with no warranty. You may share and change it under the terms of '
            'that license.',
          ),
          const _Heading('Source code'),
          const _Link(sourceUrl),
          const _Heading('Terminal engine'),
          const Text(
            'The terminal is drawn by a fork of xterm.dart (MIT license), '
            'pinned to an exact commit. What the fork changes and why is '
            'described in docs/xterm-fork.md in the source:',
          ),
          const SizedBox(height: 8),
          const _Link(xtermForkDocUrl),
          const SizedBox(height: 8),
          const Text('The fork itself:'),
          const SizedBox(height: 8),
          const _Link(xtermForkUrl),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: const Text('Open-source licenses'),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Pure-Shell',
              applicationVersion: _version?.name,
              applicationLegalese: copyrightLine,
            ),
          ),
          const SizedBox(height: 24),
          Text(copyrightLine, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// A link as selectable monospace text with a copy button (no browser).
class _Link extends StatelessWidget {
  const _Link(this.url);

  final String url;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SelectableText(url, style: monoStyle.copyWith(fontSize: 13)),
        ),
        IconButton(
          tooltip: 'Copy link',
          icon: const Icon(Icons.copy, size: 20),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Link copied')));
            }
          },
        ),
      ],
    );
  }
}
