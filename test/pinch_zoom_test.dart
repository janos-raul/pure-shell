// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/ui/terminal/pinch_zoom.dart';

void main() {
  Future<void> pump(
    WidgetTester t,
    List<double> changes,
    List<double> ends, {
    VoidCallback? onTap,
  }) async {
    var value = 11.0;
    await t.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => PinchZoom(
            value: value,
            onChanged: (v) {
              changes.add(v);
              setState(() => value = v);
            },
            onChangeEnd: ends.add,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('spreading two fingers enlarges the font, once at the end', (
    t,
  ) async {
    final changes = <double>[], ends = <double>[];
    await pump(t, changes, ends);
    final a = await t.startGesture(const Offset(300, 400), pointer: 1);
    final b = await t.startGesture(const Offset(400, 400), pointer: 2);
    await a.moveTo(const Offset(250, 400));
    await b.moveTo(const Offset(450, 400)); // distance 100 -> 200: x2
    await a.up();
    await b.up();
    expect(changes, isNotEmpty);
    expect(changes.last, 22.0);
    expect(ends, [22.0]);
  });

  testWidgets('pinching in shrinks it and the size is clamped', (t) async {
    final changes = <double>[], ends = <double>[];
    await pump(t, changes, ends);
    final a = await t.startGesture(const Offset(100, 400), pointer: 1);
    final b = await t.startGesture(const Offset(500, 400), pointer: 2);
    await a.moveTo(const Offset(299, 400));
    await b.moveTo(const Offset(301, 400)); // nearly zero distance
    await a.up();
    await b.up();
    expect(changes.last, 7.0); // minimum
    expect(ends, [7.0]);
  });

  testWidgets('one finger does not zoom and taps still reach the child', (
    t,
  ) async {
    final changes = <double>[], ends = <double>[];
    var taps = 0;
    await pump(t, changes, ends, onTap: () => taps++);
    await t.tapAt(const Offset(200, 200));
    final g = await t.startGesture(const Offset(200, 200));
    await g.moveTo(const Offset(260, 300));
    await g.up();
    expect(changes, isEmpty);
    expect(ends, isEmpty);
    expect(taps, 1);
  });
}
