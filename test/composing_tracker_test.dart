// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/input/composing_tracker.dart';

/// What the server ends up with: apply deltas to a line.
String _apply(String line, InputDelta d) =>
    line.substring(0, line.length - d.backspaces) + d.text;

void main() {
  test('a growing word sends only the new letters (no hhehel)', () {
    final t = ComposingTracker();
    expect(t.setComposing('h'), const InputDelta(0, 'h'));
    expect(t.setComposing('he'), const InputDelta(0, 'e'));
    expect(t.setComposing('hel'), const InputDelta(0, 'l'));
    expect(t.setComposing('hell'), const InputDelta(0, 'l'));
    expect(t.setComposing('hello'), const InputDelta(0, 'o'));
  });

  test(
    'autocorrect replacement: backspaces for what changed, then the new',
    () {
      final t = ComposingTracker();
      var line = '';
      for (final w in ['t', 'te', 'teh']) {
        line = _apply(line, t.setComposing(w));
      }
      expect(line, 'teh');
      final d = t.setComposing('the');
      expect(d, const InputDelta(2, 'he'));
      line = _apply(line, d);
      expect(line, 'the');
    },
  );

  test('backspace inside the word', () {
    final t = ComposingTracker();
    var line = '';
    for (final w in ['h', 'he', 'hel', 'hell', 'hello']) {
      line = _apply(line, t.setComposing(w));
    }
    // The keyboard deletes one letter and reports the shorter word.
    final shorter = t.setComposing('hell');
    expect(shorter, const InputDelta(1, ''));
    line = _apply(line, shorter);
    expect(line, 'hell');
    // Deleting from the middle: "hello" -> "helo".
    final t2 = ComposingTracker()..setComposing('hello');
    final d = t2.setComposing('helo');
    expect(_apply('hello', d), 'helo');
  });

  test('commit applies the final delta and resets the tracking', () {
    final t = ComposingTracker();
    var line = '';
    for (final w in ['h', 'he', 'hel']) {
      line = _apply(line, t.setComposing(w));
    }
    final d = t.commit('hello ');
    expect(d, const InputDelta(0, 'lo '));
    line = _apply(line, d);
    expect(line, 'hello ');
    expect(t.sent, '');
    // The next word starts from nothing: no backspaces into the last one.
    expect(t.setComposing('w'), const InputDelta(0, 'w'));
  });

  test('a commit that corrects the composing word', () {
    final t = ComposingTracker()..setComposing('teh');
    expect(t.commit('the '), const InputDelta(2, 'he '));
  });

  test('swipe typing: a whole word committed at once is sent as it is', () {
    final t = ComposingTracker();
    expect(t.commit('hello'), const InputDelta(0, 'hello'));
    expect(t.commit(' world'), const InputDelta(0, ' world'));
    expect(t.sent, '');
  });

  test('finishing the span keeps what was sent and starts over', () {
    final t = ComposingTracker()..setComposing('abc');
    t.finish();
    expect(t.setComposing('d'), const InputDelta(0, 'd'));
  });

  test('delete before the cursor shortens the tracked span', () {
    final t = ComposingTracker()..setComposing('hello');
    expect(t.deleteBefore(1), const InputDelta(1, ''));
    // The keyboard now reports "help": only the changed tail is sent.
    expect(t.setComposing('help'), const InputDelta(1, 'p'));
    expect(t.deleteBefore(10), const InputDelta(10, ''));
    expect(t.sent, '');
  });

  test('characters outside the BMP count as one', () {
    final t = ComposingTracker()..setComposing('a😀');
    expect(t.setComposing('a'), const InputDelta(1, ''));
  });
}
