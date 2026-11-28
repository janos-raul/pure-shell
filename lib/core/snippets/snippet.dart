// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:math';

/// What tapping a snippet does: put it in the command box to edit first, or
/// send it to the server followed by Enter.
enum SnippetMode { insert, run }

/// A saved command (or several lines). Global, or tied to one host.
///
/// Snippets live in encrypted storage like hosts, but they are meant for
/// commands, not secrets: the editor says so.
class Snippet {
  const Snippet({
    required this.id,
    required this.name,
    required this.text,
    this.hostId,
    this.mode = SnippetMode.insert,
    this.confirm = false,
  });

  final String id;
  final String name;

  /// The command text; may have several lines.
  final String text;

  /// The host this snippet belongs to, or null for a global snippet.
  final String? hostId;

  final SnippetMode mode;

  /// Run mode: ask before sending. Has no effect on insert snippets (nothing
  /// is sent until the user presses Send).
  final bool confirm;

  bool get isGlobal => hostId == null;
  bool get isMultiLine => text.contains('\n') || text.contains('\r');

  /// What "ask before running" should start as for [text]: on when it has
  /// several lines, off for one line.
  static bool confirmDefaultFor(String text) =>
      text.contains('\n') || text.contains('\r');

  static String newId() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Snippet copyWith({
    String? name,
    String? text,
    String? hostId,
    bool clearHost = false,
    SnippetMode? mode,
    bool? confirm,
  }) => Snippet(
    id: id,
    name: name ?? this.name,
    text: text ?? this.text,
    hostId: clearHost ? null : (hostId ?? this.hostId),
    mode: mode ?? this.mode,
    confirm: confirm ?? this.confirm,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'text': text,
    if (hostId != null) 'hostId': hostId,
    'mode': mode.name,
    'confirm': confirm,
  };

  factory Snippet.fromJson(Map<String, dynamic> json) => Snippet(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    text: json['text'] as String? ?? '',
    hostId: json['hostId'] as String?,
    mode: SnippetMode.values.asNameMap()[json['mode']] ?? SnippetMode.insert,
    confirm: json['confirm'] == true,
  );

  @override
  bool operator ==(Object other) =>
      other is Snippet &&
      other.id == id &&
      other.name == name &&
      other.text == text &&
      other.hostId == hostId &&
      other.mode == mode &&
      other.confirm == confirm;

  @override
  int get hashCode => Object.hash(id, name, text, hostId, mode, confirm);
}
