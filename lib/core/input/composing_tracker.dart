// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

/// What to send to the server for one keyboard event: [backspaces] DELs
/// first, then [text].
class InputDelta {
  const InputDelta(this.backspaces, this.text);

  static const none = InputDelta(0, '');

  final int backspaces;
  final String text;

  bool get isEmpty => backspaces == 0 && text.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is InputDelta &&
      other.backspaces == backspaces &&
      other.text == text;

  @override
  int get hashCode => Object.hash(backspaces, text);

  @override
  String toString() => 'InputDelta($backspaces, "$text")';
}

/// Turns the keyboard's composing-text events into what has to be sent.
///
/// A keyboard that keeps a word "composing" (h, he, hel, hell, hello) reports
/// the whole word each time. Everything typed is sent at once, so this tracks
/// what has been sent for the current composing span and returns only the
/// difference: backspaces for characters that were taken back (autocorrect,
/// delete inside the word), then the new characters.
///
/// Characters are counted as code points, which is what one Backspace removes.
class ComposingTracker {
  var _sent = <int>[];

  /// The composing span as sent so far (for tests).
  String get sent => String.fromCharCodes(_sent);

  /// The keyboard's composing text is now [text].
  InputDelta setComposing(String text) => _move(text.runes.toList());

  /// The keyboard commits [text]; it replaces the composing span, if any.
  /// Tracking starts again afterwards.
  InputDelta commit(String text) {
    final delta = _move(text.runes.toList());
    _sent = [];
    return delta;
  }

  /// The composing span ended without new text: what was sent stays.
  void finish() => _sent = [];

  /// The keyboard deleted [before] characters before the cursor. They are
  /// removed from the tracked span as well, so the next composing update is
  /// compared with what is really on the server.
  InputDelta deleteBefore(int before) {
    if (before <= 0) return InputDelta.none;
    final keep = before >= _sent.length ? 0 : _sent.length - before;
    _sent = _sent.sublist(0, keep);
    return InputDelta(before, '');
  }

  InputDelta _move(List<int> target) {
    var common = 0;
    final max = _sent.length < target.length ? _sent.length : target.length;
    while (common < max && _sent[common] == target[common]) {
      common++;
    }
    final delta = InputDelta(
      _sent.length - common,
      String.fromCharCodes(target.sublist(common)),
    );
    _sent = target;
    return delta;
  }
}
