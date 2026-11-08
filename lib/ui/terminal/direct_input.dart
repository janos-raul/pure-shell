// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../core/input/composing_tracker.dart';

/// "Direct" input: every character reaches the server as soon as it is typed.
///
/// A small invisible native view owns the soft keyboard (type NULL, like
/// Termux) and reports what the keyboard does over a channel. This class turns
/// those events into terminal input:
///
/// - typed text, composing deltas and key presses -> `terminal.textInput`
///   (so sticky Ctrl and the output path stay as they are);
/// - Enter (a lone newline, or the keyboard's enter action) -> Enter key (\r);
/// - Backspace -> 0x7f;
/// - a commit that contains a newline together with other text -> the
///   terminal's paste path (bracketed paste when the program asked for it).
///
/// Events that arrive while [accepting] is false (locked, backgrounded, no
/// session) are dropped, and the native view is detached.
class DirectInput {
  DirectInput({
    required this.terminal,
    required this.accepting,
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const channelName = 'eu.pureshell.app/terminal_input';

  final Terminal terminal;

  /// Whether typed input may reach the server right now.
  final bool Function() accepting;

  final MethodChannel _channel;
  final _tracker = ComposingTracker();

  /// Gives the native view the keyboard focus and shows the keyboard.
  Future<void> attach() async {
    if (!accepting()) return;
    await _invoke('attach');
  }

  /// Takes the keyboard away from the native view and forgets any composing
  /// span.
  Future<void> detach({bool hide = true}) async {
    _tracker.finish();
    await _invoke('detach', {'hide': hide});
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _invoke('detach', {'hide': true});
  }

  Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No native side (tests).
    }
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'event') return;
    handle(Map<String, dynamic>.from(call.arguments as Map));
  }

  /// Handles one event from the native view.
  @visibleForTesting
  void handle(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'blur') {
      _tracker.finish();
      return;
    }
    if (!accepting()) {
      _tracker.finish();
      return;
    }
    // Debug builds only, and only which path the input took, never what.
    if (kDebugMode) {
      debugPrint('[input] path=${_pathName(type)}');
    }
    final text = (event['text'] as String?) ?? '';
    switch (type) {
      case 'composing':
        _send(_tracker.setComposing(text));
      case 'commit':
        _send(_tracker.commit(text));
      case 'finish':
        _tracker.finish();
      case 'delete':
        _send(_tracker.deleteBefore((event['before'] as int?) ?? 0));
      case 'key-text':
        // A key press that produced a character: typed as it is.
        _tracker.finish();
        if (text.isNotEmpty) terminal.textInput(text);
      case 'enter':
        _tracker.finish();
        terminal.keyInput(TerminalKey.enter);
    }
  }

  static String _pathName(String? type) => switch (type) {
    'key-text' => 'key-event',
    'enter' => 'editor-action',
    'delete' => 'text-delete',
    _ => 'text-$type',
  };

  static bool _hasNewline(String text) =>
      text.contains('\n') || text.contains('\r');

  /// Text that contains a line break: a lone break is the Enter key, anything
  /// else is a paste (line breaks become \r, what Enter sends).
  void _lines(String text) {
    if (text == '\n' || text == '\r' || text == '\r\n') {
      terminal.keyInput(TerminalKey.enter);
      return;
    }
    terminal.paste(text.replaceAll('\r\n', '\r').replaceAll('\n', '\r'));
  }

  /// Sends what is new: backspaces first, then the text. A line break in the
  /// new text is Enter (alone) or a paste (with other text), and ends the
  /// composing span.
  void _send(InputDelta delta) {
    for (var i = 0; i < delta.backspaces; i++) {
      terminal.keyInput(TerminalKey.backspace);
    }
    if (delta.text.isEmpty) return;
    if (_hasNewline(delta.text)) {
      _lines(delta.text);
      _tracker.finish();
    } else {
      terminal.textInput(delta.text);
    }
  }
}
