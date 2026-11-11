// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/ui/terminal/desktop_keys.dart';

DesktopKeyAction? act(
  LogicalKeyboardKey k, {
  bool ctrl = false,
  bool shift = false,
  bool alt = false,
  String? char,
}) => desktopKeyAction(k, ctrl: ctrl, shift: shift, alt: alt, character: char);

void main() {
  test('Ctrl+Shift+C / Ctrl+Shift+V / Shift+Insert are copy and paste', () {
    expect(
      act(LogicalKeyboardKey.keyC, ctrl: true, shift: true),
      isA<CopyAction>(),
    );
    expect(
      act(LogicalKeyboardKey.keyV, ctrl: true, shift: true),
      isA<PasteAction>(),
    );
    expect(act(LogicalKeyboardKey.insert, shift: true), isA<PasteAction>());
  });

  test('plain Ctrl and Alt combinations go to the shell', () {
    for (final k in [
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.keyX,
    ]) {
      expect(act(k, ctrl: true, char: '\x01'), isNull, reason: '$k');
      expect(act(k, alt: true), isNull, reason: '$k');
    }
    // Ctrl+_ (readline undo) is not zoom-out.
    expect(act(LogicalKeyboardKey.minus, ctrl: true, shift: true), isNull);
  });

  test('font zoom keys', () {
    ZoomAction? z(LogicalKeyboardKey k, {bool shift = false}) =>
        act(k, ctrl: true, shift: shift) as ZoomAction?;
    expect(z(LogicalKeyboardKey.equal)!.step, 1);
    expect(z(LogicalKeyboardKey.equal, shift: true)!.step, 1); // Ctrl++
    expect(z(LogicalKeyboardKey.numpadAdd)!.step, 1);
    expect(z(LogicalKeyboardKey.minus)!.step, -1);
    expect(z(LogicalKeyboardKey.numpadSubtract)!.step, -1);
    expect(z(LogicalKeyboardKey.digit0)!.step, 0);
    expect(act(LogicalKeyboardKey.equal), isNull); // no Ctrl: just "="
  });

  test('Alt+key is ESC + the character as typed (case kept)', () {
    final b = act(LogicalKeyboardKey.keyB, alt: true, char: 'b');
    expect((b! as TypeAction).text, '\x1bb');
    final upper = act(
      LogicalKeyboardKey.keyB,
      alt: true,
      shift: true,
      char: 'B',
    );
    expect((upper! as TypeAction).text, '\x1bB');
  });

  test('AltGr characters are typed, not sent as Ctrl+Alt', () {
    final a = act(LogicalKeyboardKey.keyQ, ctrl: true, alt: true, char: '@');
    expect(a, isA<TypeAction>());
    expect((a! as TypeAction).text, '@');
    // Ctrl+Alt+key without a printable character stays with the shell.
    expect(act(LogicalKeyboardKey.keyQ, ctrl: true, alt: true), isNull);
  });
}
