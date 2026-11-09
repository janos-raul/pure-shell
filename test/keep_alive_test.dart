// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/ssh/keep_alive.dart';

void main() {
  test('defaults: ping every 30 s, 15 s to answer, two misses in a row', () {
    expect(keepAliveInterval, const Duration(seconds: 30));
    expect(keepAliveReplyTimeout, const Duration(seconds: 15));
    expect(keepAliveMaxMissed, 2);
  });

  group('SessionKeepAlive', () {
    Future<void> advance(WidgetTester t, int seconds) async {
      for (var i = 0; i < seconds; i++) {
        await t.pump(const Duration(seconds: 1));
      }
    }

    testWidgets('answered pings keep the connection', (t) async {
      var pings = 0;
      var dead = 0;
      final k = SessionKeepAlive(
        ping: () async => pings++,
        onDead: () => dead++,
      )..start();
      await advance(t, 95);
      expect(pings, 3); // at 30, 60, 90 s
      expect(dead, 0);
      k.stop();
    });

    testWidgets('two unanswered pings in a row end it, once', (t) async {
      var pings = 0;
      var dead = 0;
      final k = SessionKeepAlive(
        ping: () {
          pings++;
          return Completer<void>().future; // never answered
        },
        onDead: () => dead++,
      )..start();
      await advance(t, 44);
      expect(dead, 0); // first ping sent at 30 s, times out at 45 s
      await advance(t, 40); // second ping at 60 s, times out at 75 s
      expect(pings, 2);
      expect(dead, 1);
      expect(k.running, isFalse);
      await advance(t, 120);
      expect(dead, 1); // not again
    });

    testWidgets('a ping that throws counts as a miss', (t) async {
      var dead = 0;
      final k = SessionKeepAlive(
        ping: () async => throw StateError('closed'),
        onDead: () => dead++,
      )..start();
      await advance(t, 65);
      expect(dead, 1);
      k.stop();
    });

    testWidgets('one miss followed by an answer is forgiven', (t) async {
      var n = 0;
      var dead = 0;
      final k = SessionKeepAlive(
        ping: () {
          n++;
          // The 1st and 3rd pings get no answer, the 2nd and 4th do.
          return n.isOdd ? Completer<void>().future : Future<void>.value();
        },
        onDead: () => dead++,
      )..start();
      await advance(t, 140); // pings at 30, 60, 90, 120 s
      expect(n, 4);
      expect(dead, 0);
      k.stop();
    });

    testWidgets('stop() ends the pinging', (t) async {
      var pings = 0;
      final k = SessionKeepAlive(ping: () async => pings++, onDead: () {})
        ..start();
      await advance(t, 35);
      k.stop();
      await advance(t, 120);
      expect(pings, 1);
    });

    testWidgets('custom interval, timeout and limit are honoured', (t) async {
      var dead = 0;
      final k = SessionKeepAlive(
        interval: const Duration(seconds: 5),
        replyTimeout: const Duration(seconds: 2),
        maxMissed: 3,
        ping: () => Completer<void>().future,
        onDead: () => dead++,
      )..start();
      await advance(t, 18); // misses at 7, 12, 17 s
      expect(dead, 1);
      k.stop();
    });
  });
}
