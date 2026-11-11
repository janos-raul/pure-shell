// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/ui/help/help_content.dart';
import 'package:pureshell/ui/keys/keys_screen.dart';

Iterable<String> _texts(HelpTopic t) sync* {
  yield t.title;
  yield t.summary;
  for (final b in t.blocks) {
    switch (b) {
      case HelpHeading(:final text) || HelpText(:final text):
        yield text;
      case HelpSteps(:final steps):
        yield* steps;
      case HelpCommand(:final command):
        yield command;
    }
  }
}

T _onWindows<T>(T Function() body) {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  try {
    return body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  final phoneWords = RegExp(
    r'\b(phone|Android|tap|Tap|screen lock|Keystore|StrongBox|TEE|swipe)\b',
  );

  test('the Windows help says nothing about phones', () {
    final topics = _onWindows(() => helpTopics);
    expect(
      topics.map((t) => t.id),
      containsAll([helpAddKey, helpFirstConnect]),
    );
    for (final t in topics) {
      for (final text in _texts(t)) {
        expect(phoneWords.hasMatch(text), isFalse, reason: '${t.id}: $text');
      }
    }
  });

  test('the Android help is the one tests were written for', () {
    expect(helpTopics.map((t) => t.id), contains('keep-alive'));
  });

  test('the Windows key-loss notice talks about Windows Hello', () {
    expect(phoneWords.hasMatch(windowsKeyLossNotice), isFalse);
    expect(windowsKeyLossNotice, contains('Windows Hello'));
  });
}
