// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:xterm/xterm.dart';

import '../../core/snippets/snippet.dart';

/// Line breaks as the terminal expects them (a typed Enter is CR), with the
/// breaks at the very end removed: they would run the command before the
/// final Enter this adds.
String normalizeSnippetText(String text) => text
    .replaceAll('\r\n', '\r')
    .replaceAll('\n', '\r')
    .replaceAll(RegExp(r'\r+$'), '');

/// Whether tapping [snippet] must ask first: only run snippets send anything.
bool snippetNeedsConfirm(Snippet snippet) =>
    snippet.mode == SnippetMode.run && snippet.confirm;

/// Sends a run snippet.
///
/// One line is typed as it is followed by Enter ([send]). Several lines go in
/// as a paste, bracketed when the program asked for it, so a shell does not
/// start the first line before it has read the rest; then one Enter runs it.
/// The "Paste N lines?" question of a normal paste is not asked: choosing Run
/// was deliberate. Returns false when there is nothing to send.
bool runSnippetText(
  String text, {
  required Terminal terminal,
  required void Function(String data) send,
}) {
  final body = normalizeSnippetText(text);
  if (body.trim().isEmpty) return false;
  if (body.contains('\r')) {
    terminal.paste(body);
    send('\r');
  } else {
    send('$body\r');
  }
  return true;
}
