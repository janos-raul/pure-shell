// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/snippets/snippet.dart';
import 'package:pureshell/ui/terminal/snippet_runner.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('normalizeSnippetText', () {
    test('line breaks become CR, breaks at the end are dropped', () {
      expect(normalizeSnippetText('a\nb'), 'a\rb');
      expect(normalizeSnippetText('a\r\nb\r\n'), 'a\rb');
      expect(normalizeSnippetText('ls\n\n'), 'ls');
    });
  });

  group('snippetNeedsConfirm', () {
    test('only run snippets with the switch on', () {
      Snippet s(SnippetMode m, bool c) =>
          Snippet(id: 'a', name: 'n', text: 'ls', mode: m, confirm: c);
      expect(snippetNeedsConfirm(s(SnippetMode.run, true)), isTrue);
      expect(snippetNeedsConfirm(s(SnippetMode.run, false)), isFalse);
      expect(snippetNeedsConfirm(s(SnippetMode.insert, true)), isFalse);
    });
  });

  group('runSnippetText', () {
    late Terminal terminal;
    late List<String> output; // what reaches the server, in order
    late List<String> sent; // what the screen's own send() got

    setUp(() {
      terminal = Terminal();
      output = [];
      sent = [];
      terminal.onOutput = output.add;
    });

    bool run(String text) => runSnippetText(
      text,
      terminal: terminal,
      send: (d) {
        sent.add(d);
        output.add(d);
      },
    );

    test('one line is sent with Enter, not as a paste', () {
      expect(run('uptime'), isTrue);
      expect(sent, ['uptime\r']);
      expect(output, ['uptime\r']);
    });

    test('a trailing line break does not run the line twice', () {
      run('uptime\n');
      expect(output, ['uptime\r']);
    });

    test('several lines are one paste, then one Enter', () {
      run('cd /tmp\nls');
      expect(output, ['cd /tmp\rls', '\r']);
    });

    test('bracketed paste is used when the program asked for it', () {
      terminal.write('\x1b[?2004h');
      run('cd /tmp\nls');
      expect(output, ['\x1b[200~cd /tmp\rls\x1b[201~', '\r']);
    });

    test('without it the lines go in plain, no markers', () {
      run('a\nb');
      expect(output.join(), isNot(contains('\x1b[200~')));
    });

    test('empty or blank text sends nothing', () {
      expect(run(''), isFalse);
      expect(run('  \n '), isFalse);
      expect(output, isEmpty);
    });
  });
}
