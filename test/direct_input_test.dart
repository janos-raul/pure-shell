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
import 'package:pureshell/ui/terminal/direct_input.dart';
import 'package:xterm/xterm.dart';

class _Rig {
  _Rig() {
    terminal.onOutput = out.add;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(DirectInput.channelName),
          (call) async {
            calls.add(call.method);
            return null;
          },
        );
    input = DirectInput(terminal: terminal, accepting: () => accepting);
  }

  final terminal = Terminal();
  final out = <String>[];
  final calls = <String>[];
  var accepting = true;
  late final DirectInput input;

  String get sent => out.join();

  void ev(String type, [String text = '', Map<String, dynamic>? extra]) =>
      input.handle({'type': type, 'text': text, ...?extra});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(DirectInput.channelName),
          null,
        );
  });

  test('typed letters reach the server as they are typed', () {
    final r = _Rig();
    r.ev('composing', 'l');
    expect(r.sent, 'l');
    r.ev('composing', 'ls');
    expect(r.sent, 'ls'); // not "lls"
    r.ev('commit', 'ls');
    expect(r.sent, 'ls');
  });

  test(
    'Enter: a lone newline commit, the editor action, and a key all send \\r',
    () {
      final r = _Rig();
      r.ev('commit', '\n');
      r.ev('enter');
      expect(r.sent, '\r\r');
    },
  );

  test('Backspace sends 0x7f, also for deleteSurroundingText', () {
    final r = _Rig();
    r.ev('delete', '', {'before': 2});
    expect(r.sent, '\x7f\x7f');
  });

  test('a key press that typed a character is sent as text', () {
    final r = _Rig();
    r.ev('key-text', 'é');
    expect(r.sent, 'é');
  });

  test(
    'a commit with text and a newline is a paste (bracketed when asked)',
    () {
      final r = _Rig();
      r.ev('commit', 'echo a\necho b');
      expect(r.sent, 'echo a\recho b'); // plain: line breaks become \r

      r.out.clear();
      r.terminal.write('\x1b[?2004h'); // the program asks for bracketed paste
      r.ev('commit', 'echo a\necho b');
      expect(r.sent, '\x1b[200~echo a\recho b\x1b[201~');
    },
  );

  test('a commit with a newline after composing text does not repeat it', () {
    final r = _Rig();
    r.ev('composing', 'ab'); // already sent
    r.ev('commit', 'ab\n'); // replaces the span: only the break is new
    expect(r.sent, 'ab\r');
  });

  group('input is dead when it must not be accepted', () {
    test('events are dropped while not accepting', () {
      final r = _Rig()..accepting = false;
      r.ev('commit', 'secret');
      r.ev('composing', 'x');
      r.ev('key-text', 'y');
      r.ev('enter');
      r.ev('delete', '', {'before': 1});
      r.ev('commit', 'a\nb');
      expect(r.sent, '');
    });

    test('a dropped composing span is not resumed afterwards', () {
      final r = _Rig();
      r.ev('composing', 'ab');
      r.accepting = false;
      r.ev('composing', 'abc'); // dropped
      r.accepting = true;
      r.ev('composing', 'd');
      // Nothing is backspaced into text the server may not have.
      expect(r.sent, 'abd');
    });

    test('attach does nothing while not accepting', () async {
      final r = _Rig()..accepting = false;
      await r.input.attach();
      expect(r.calls, isEmpty);
      r.accepting = true;
      await r.input.attach();
      expect(r.calls, ['attach']);
    });

    test('detach always reaches the native view', () async {
      final r = _Rig()..accepting = false;
      await r.input.detach();
      expect(r.calls, ['detach']);
    });
  });
}
