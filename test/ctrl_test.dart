// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/ui/terminal/terminal_screen.dart';

void main() {
  test('sticky Ctrl maps letters to control characters', () {
    expect(applyCtrl('c'), '\x03');
    expect(applyCtrl('C'), '\x03');
    expect(applyCtrl('d'), '\x04');
    expect(applyCtrl('['), '\x1b');
  });

  test('Ctrl leaves multi-character input and digits alone', () {
    expect(applyCtrl('ab'), isNull);
    expect(applyCtrl('1'), isNull);
  });
}
