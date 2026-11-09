// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';

import '../command_block.dart';
import '../theme.dart';
import 'help_content.dart';

/// Splits help text into spans: `code` in monospace, **bold** in bold.
List<InlineSpan> helpSpans(String text) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'`([^`]+)`|\*\*([^*]+)\*\*');
  var at = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(text: m.group(1), style: monoStyle));
    } else {
      spans.add(
        TextSpan(
          text: m.group(2),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
    }
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

/// The help: a list of short topics, offline.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView(
        children: [
          for (final topic in helpTopics)
            ListTile(
              title: Text(topic.title),
              subtitle: Text(topic.summary),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => HelpTopicScreen(topic: topic),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens one topic directly (links from other screens).
void openHelpTopic(BuildContext context, String id) {
  final topic = helpTopicById(id);
  if (topic == null) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => HelpTopicScreen(topic: topic)),
  );
}

class HelpTopicScreen extends StatelessWidget {
  const HelpTopicScreen({super.key, required this.topic});

  final HelpTopic topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge;
    return Scaffold(
      appBar: AppBar(title: Text(topic.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final block in topic.blocks)
            Padding(
              padding: EdgeInsets.only(
                top: block is HelpHeading ? 20 : 0,
                bottom: 12,
              ),
              child: switch (block) {
                HelpHeading() => Text(
                  block.text,
                  style: theme.textTheme.titleMedium,
                ),
                HelpText() => Text.rich(
                  TextSpan(children: helpSpans(block.text)),
                  style: body,
                ),
                HelpSteps() => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < block.steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 28,
                              child: Text('${i + 1}.', style: body),
                            ),
                            Expanded(
                              child: Text.rich(
                                TextSpan(children: helpSpans(block.steps[i])),
                                style: body,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                HelpCommand() => CommandBlock(block.command),
              },
            ),
        ],
      ),
    );
  }
}
