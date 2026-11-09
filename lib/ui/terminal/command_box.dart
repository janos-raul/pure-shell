// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';

/// Moves a text cursor one step: [dx] characters left/right, or [dy] lines
/// up/down (keeping the column where the line is long enough). Up on the first
/// line goes to the start, down on the last line to the end.
int moveCaret(String text, int offset, {int dx = 0, int dy = 0}) {
  var at = offset.clamp(0, text.length);
  if (dx != 0) return (at + dx).clamp(0, text.length);
  if (dy == 0) return at;
  final lineStart = at == 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;
  final column = at - lineStart;
  if (dy < 0) {
    if (lineStart == 0) return 0;
    final prevStart = lineStart < 2
        ? 0
        : text.lastIndexOf('\n', lineStart - 2) + 1;
    final prevLength = lineStart - 1 - prevStart;
    return prevStart + (column < prevLength ? column : prevLength);
  }
  final lineEnd = text.indexOf('\n', at);
  if (lineEnd < 0) return text.length;
  final nextStart = lineEnd + 1;
  final nextEnd = text.indexOf('\n', nextStart);
  final nextLength = (nextEnd < 0 ? text.length : nextEnd) - nextStart;
  return nextStart + (column < nextLength ? column : nextLength);
}

/// Replaces the selection of [controller] with [text] (inserts at the cursor).
void insertAtCursor(TextEditingController controller, String text) {
  final value = controller.value;
  final sel = value.selection;
  final start = sel.isValid ? sel.start : value.text.length;
  final end = sel.isValid ? sel.end : value.text.length;
  controller.value = TextEditingValue(
    text: value.text.replaceRange(start, end, text),
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}

/// The command-line box above the keyboard: a normal text field (swipe typing,
/// suggestions, autocorrect) whose whole content is sent on confirm. The
/// keyboard is asked not to learn from it (users may type passwords here).
///
/// It owns no state of its own: the screen holds the controller, so it can
/// clear it when the box closes or the app is covered. Nothing typed here is
/// stored, logged or kept as history.
class CommandLineBox extends StatelessWidget {
  const CommandLineBox({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.keepOpen,
    required this.onKeepOpenChanged,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool keepOpen;
  final ValueChanged<bool> onKeepOpenChanged;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xFF121212),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('command-box-field'),
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                // Not single-line: Flutter drops pasted line breaks in a
                // one-line field. It looks like one line until a multi-line
                // text is pasted; a typed Enter at the end sends.
                minLines: 1,
                maxLines: 3,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.send,
                // Suggestions and swipe stay; nothing is replaced behind the
                // user's back (ls -> Is, cd -> CD would break commands).
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                enableSuggestions: true,
                enableIMEPersonalizedLearning: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                autofillHints: const [],
                onChanged: onChanged,
                onSubmitted: (_) => onSend(),
                onEditingComplete: () {}, // keep the focus; the screen decides
                decoration: const InputDecoration(
                  hintText: 'Command line',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              tooltip: keepOpen
                  ? 'Stays open after sending'
                  : 'Closes after sending',
              isSelected: keepOpen,
              icon: const Icon(Icons.push_pin_outlined),
              selectedIcon: Icon(Icons.push_pin, color: scheme.primary),
              onPressed: () => onKeepOpenChanged(!keepOpen),
            ),
            IconButton(
              tooltip: 'Send',
              icon: Icon(Icons.send, color: scheme.primary),
              onPressed: onSend,
            ),
          ],
        ),
      ),
    );
  }
}
