// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/ui/terminal/pty_resize.dart';

void main() {
  late List<(int, int)> sent;
  late PtyResizeCoalescer c;

  setUp(() {
    sent = [];
    c = PtyResizeCoalescer(send: (cols, rows) => sent.add((cols, rows)));
  });

  tearDown(() => c.dispose());

  test('nothing is sent during a hold; release sends the final size once', () {
    fakeAsync((async) {
      c.markSent(80, 24);
      c.hold();
      for (var i = 1; i <= 30; i++) {
        c.request(80 - i, 24 - i ~/ 3); // 30 pinch steps
        async.elapse(const Duration(milliseconds: 16));
      }
      async.elapse(const Duration(seconds: 2));
      expect(sent, isEmpty, reason: 'no resize while the fingers are down');

      c.release();
      expect(sent, [(50, 14)]);
      async.elapse(const Duration(seconds: 2));
      expect(sent, hasLength(1));
    });
  });

  test('a size that did not change is never sent', () {
    fakeAsync((async) {
      c.markSent(80, 24);
      c.request(80, 24);
      async.elapse(const Duration(seconds: 1));
      expect(sent, isEmpty);

      // Pinched away and back to the same grid: still nothing to send.
      c.hold();
      c.request(60, 20);
      c.request(80, 24);
      c.release();
      expect(sent, isEmpty);
    });
  });

  test('the same size is not sent twice in a row', () {
    fakeAsync((async) {
      c.request(100, 30);
      async.elapse(const Duration(milliseconds: 200));
      c.request(100, 30);
      async.elapse(const Duration(milliseconds: 200));
      expect(sent, [(100, 30)]);
      c.request(100, 31);
      async.elapse(const Duration(milliseconds: 200));
      expect(sent, [(100, 30), (100, 31)]);
    });
  });

  test('without a hold, a burst is debounced to one send after ~150 ms', () {
    fakeAsync((async) {
      c.markSent(80, 24);
      for (var i = 0; i < 10; i++) {
        c.request(80, 24 - i); // e.g. the keyboard animating in
        async.elapse(const Duration(milliseconds: 20));
      }
      expect(sent, isEmpty, reason: 'still changing');
      async.elapse(const Duration(milliseconds: 160));
      expect(sent, [(80, 15)]);
    });
  });

  test('a hold cancels a pending debounced send', () {
    fakeAsync((async) {
      c.markSent(80, 24);
      c.request(70, 20);
      c.hold();
      async.elapse(const Duration(seconds: 1));
      expect(sent, isEmpty);
      c.release();
      expect(sent, [(70, 20)]);
    });
  });

  test('a resize lost while the shell opened is sent once it is open', () {
    fakeAsync((async) {
      // The shell opens with 80x26; meanwhile the extra-keys bar appears
      // (80x24) and that send finds no session yet, so it goes nowhere.
      c.request(80, 24);
      async.elapse(const Duration(milliseconds: 200));
      // Shell open: the server has the size it was opened with, and the
      // screen asks for the size the view has now.
      c.markSent(80, 26);
      c.request(80, 24);
      async.elapse(const Duration(milliseconds: 200));
      expect(sent.last, (80, 24));

      // Had the view not changed, the same call sends nothing.
      sent.clear();
      c.markSent(80, 24);
      c.request(80, 24);
      async.elapse(const Duration(milliseconds: 200));
      expect(sent, isEmpty);
    });
  });

  test('nothing is sent after dispose; invalid sizes are ignored', () {
    fakeAsync((async) {
      c.request(0, 0);
      async.elapse(const Duration(seconds: 1));
      expect(sent, isEmpty);
      c.request(90, 30);
      c.dispose();
      async.elapse(const Duration(seconds: 1));
      expect(sent, isEmpty);
    });
  });
}
