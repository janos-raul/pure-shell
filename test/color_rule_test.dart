// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/keys/keystore_api.dart';
import 'package:pureshell/core/keys/ssh_key.dart';
import 'package:pureshell/ui/keys/key_widgets.dart';
import 'package:pureshell/ui/theme.dart';

/// THE COLOR RULE: red is only ever used on the black background, as text, an
/// outline or an icon. Never as a fill, never on or inside a green fill.
void main() {
  SshKey key(KeyKind kind, SecurityLevel level) => SshKey(
    id: 'k',
    name: 'Test key',
    kind: kind,
    level: level,
    publicKey: Uint8List(32),
    createdAt: DateTime(2026),
  );

  group('source rules (lib/ui, outside theme.dart)', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) => f.path.endsWith('.dart') && !f.path.endsWith('theme.dart'),
        )
        .toList();

    test('no red fills or red-tinted surfaces', () {
      for (final f in files) {
        final s = f.readAsStringSync();
        for (final banned in [
          'errorContainer',
          'Colors.red',
          'redAccent',
          '0xFF7A1212',
          '0xFF3B0A0A',
          'Colors.teal',
        ]) {
          expect(s.contains(banned), isFalse, reason: '${f.path}: $banned');
        }
        // A background that is the error color.
        expect(
          RegExp(
            r'[bB]ackground[A-Za-z]*:[^,;)]*error',
            caseSensitive: false,
          ).hasMatch(s),
          isFalse,
          reason: '${f.path}: a red background',
        );
      }
    });

    test('no filled or tonal button is made red', () {
      for (final f in files) {
        final s = f.readAsStringSync();
        for (final m in RegExp(r'Filled(Button|\.tonal)').allMatches(s)) {
          final near = s.substring(m.start, (m.start + 260).clamp(0, s.length));
          expect(
            RegExp(r'error|errorRed|destructive').hasMatch(near),
            isFalse,
            reason: '${f.path}: a red filled button',
          );
        }
      }
    });
  });

  group('theme', () {
    test('destructive buttons are red text (and outline) with no fill', () {
      final text = destructiveTextStyle();
      expect(text.foregroundColor?.resolve({}), errorRed);
      expect(text.backgroundColor, isNull);
      final outline = destructiveOutlineStyle();
      expect(outline.foregroundColor?.resolve({}), errorRed);
      expect(outline.side?.resolve({})?.color, errorRed);
      expect(outline.backgroundColor, isNull);
    });

    test('even an accidental errorContainer is a black fill', () {
      final scheme = pureShellTheme().colorScheme;
      expect(scheme.errorContainer, const Color(0xFF000000));
      expect(scheme.onErrorContainer, errorRed);
    });
  });

  group('security badges are outlined chips, never filled', () {
    Future<BoxDecoration> badge(WidgetTester t, SshKey k) async {
      await t.pumpWidget(
        MaterialApp(
          theme: pureShellTheme(),
          home: Scaffold(body: SecurityBadge(sshKey: k)),
        ),
      );
      final box = t.widget<Container>(
        find.descendant(
          of: find.byType(SecurityBadge),
          matching: find.byType(Container),
        ),
      );
      return box.decoration! as BoxDecoration;
    }

    final green = pureShellTheme().colorScheme.primary;

    testWidgets('StrongBox and TEE: green outline, no fill', (t) async {
      for (final level in [SecurityLevel.strongBox, SecurityLevel.tee]) {
        final d = await badge(t, key(KeyKind.hardwareEcdsa, level));
        expect(d.color, isNull);
        expect((d.border! as Border).top.color, green);
      }
    });

    testWidgets('Software: amber outline, no fill, not red', (t) async {
      final d = await badge(
        t,
        key(KeyKind.softwareEd25519, SecurityLevel.software),
      );
      expect(d.color, isNull);
      expect((d.border! as Border).top.color, warningAmber);
      final text = t.widget<Text>(find.text('Software key'));
      expect(text.style?.color, warningAmber);
    });
  });
}
