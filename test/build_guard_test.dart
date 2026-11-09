// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/keys/key_service.dart';
import 'package:pureshell/ui/build_guard.dart';

void main() {
  group('release guard', () {
    test('a release build with the emulator Keystore switch is refused', () {
      final problem = buildFlagProblem(
        releaseMode: true,
        allowSoftwareKeystore: true,
        forceSoftwareKeys: false,
      );
      expect(problem, isNotNull);
      expect(problem, contains('PURESHELL_ALLOW_SOFTWARE_KEYSTORE'));
      expect(problem, contains('release build'));
    });

    test('the forced-software switch is refused in release too', () {
      final problem = buildFlagProblem(
        releaseMode: true,
        allowSoftwareKeystore: false,
        forceSoftwareKeys: true,
      );
      expect(problem, contains('PURESHELL_FORCE_SOFTWARE_KEYS'));
    });

    test('a clean release build starts', () {
      expect(
        buildFlagProblem(
          releaseMode: true,
          allowSoftwareKeystore: false,
          forceSoftwareKeys: false,
        ),
        isNull,
      );
    });

    test('debug and profile builds may use the switches', () {
      expect(
        buildFlagProblem(
          releaseMode: false,
          allowSoftwareKeystore: true,
          forceSoftwareKeys: true,
        ),
        isNull,
      );
    });

    test('the switches are off unless passed with --dart-define', () {
      expect(allowSoftwareKeystore, isFalse);
      expect(forceSoftwareKeys, isFalse);
    });

    testWidgets('the error screen says what is wrong', (t) async {
      final problem = buildFlagProblem(
        releaseMode: true,
        allowSoftwareKeystore: true,
        forceSoftwareKeys: false,
      )!;
      await t.pumpWidget(BuildErrorApp(message: problem));
      expect(find.text('Pure-Shell refuses to start'), findsOneWidget);
      expect(
        find.textContaining('PURESHELL_ALLOW_SOFTWARE_KEYSTORE'),
        findsOneWidget,
      );
      expect(find.textContaining('Rebuild without them'), findsOneWidget);
    });
  });
}
