// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/host_repository.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/hosts/connect_flow.dart';
import 'package:pureshell/ui/hosts/host_edit_screen.dart';
import 'package:pureshell/ui/private_input.dart';
import 'package:xterm/xterm.dart';

/// Records the TextInputConfiguration JSON sent to the platform each time a
/// text input attaches to the keyboard.
List<Map<String, dynamic>> _recordKeyboardConfigs(WidgetTester tester) {
  final configs = <Map<String, dynamic>>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.textInput,
    (call) async {
      if (call.method == 'TextInput.setClient') {
        final args = call.arguments as List<dynamic>;
        configs.add(Map<String, dynamic>.from(args[1] as Map));
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      null,
    ),
  );
  return configs;
}

/// What we require of every place the user types: nothing learned, nothing
/// suggested, nothing auto-corrected.
void _expectPrivate(Map<String, dynamic> config, {required String what}) {
  expect(
    config['enableIMEPersonalizedLearning'],
    isFalse,
    reason: '$what must set IME no-personalized-learning',
  );
  expect(
    config['enableSuggestions'],
    isFalse,
    reason: '$what must disable suggestions',
  );
  expect(
    config['autocorrect'],
    isFalse,
    reason: '$what must disable autocorrect',
  );
  final type = (config['inputType'] as Map)['name'] as String;
  expect(
    type,
    isNot('TextInputType.visiblePassword'),
    reason: '$what must not use visiblePassword (Samsung layouts)',
  );
}

void _expectNoSmartPunctuation(
  Map<String, dynamic> config, {
  required String what,
}) {
  expect(config['smartDashesType'], '0', reason: '$what: smart dashes off');
  expect(config['smartQuotesType'], '0', reason: '$what: smart quotes off');
}

void main() {
  testWidgets('the terminal tells the keyboard not to learn or suggest', (
    tester,
  ) async {
    final configs = _recordKeyboardConfigs(tester);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrivateTerminalView(
            Terminal(),
            focusNode: focus,
            textStyle: const TerminalStyle(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      configs,
      isNotEmpty,
      reason: 'the terminal never attached a keyboard',
    );
    // This is what xterm itself sends. If an xterm update drops a flag, this
    // test fails. (xterm does not set smart dashes/quotes; they are iOS-only
    // settings and have no effect on Android, so they are not asserted here.)
    _expectPrivate(configs.last, what: 'terminal');
    expect(
      (configs.last['inputType'] as Map)['name'],
      PrivateTerminalView.keyboardType.toJson()['name'],
    );
  });

  testWidgets('every field of the host form is private', (tester) async {
    final configs = _recordKeyboardConfigs(tester);
    final store = MemorySecureStore();
    await tester.pumpWidget(
      MaterialApp(
        home: HostEditScreen(
          hosts: HostRepository(store),
          knownHosts: KnownHostsStore(store),
          host: const Host(
            id: '1',
            label: 'L',
            hostname: 'example.com',
            username: 'u',
          ),
        ),
      ),
    );
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(4)); // label, hostname, port, username
    for (var i = 0; i < 4; i++) {
      configs.clear();
      await tester.tap(fields.at(i));
      await tester.pump();
      expect(configs, isNotEmpty, reason: 'field $i did not attach');
      _expectPrivate(configs.last, what: 'host form field $i');
      _expectNoSmartPunctuation(configs.last, what: 'host form field $i');
    }
  });

  testWidgets('the password dialog is private', (tester) async {
    final configs = _recordKeyboardConfigs(tester);
    final store = MemorySecureStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => connectToHost(
                context,
                host: const Host(
                  id: '1',
                  label: 'T',
                  hostname: 'example.com',
                  username: 'u',
                ),
                knownHosts: KnownHostsStore(store),
                settings: TerminalSettings(store),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(configs, isNotEmpty);
    _expectPrivate(configs.last, what: 'password dialog');
    _expectNoSmartPunctuation(configs.last, what: 'password dialog');
    expect(configs.last['obscureText'], isTrue);
  });
}
