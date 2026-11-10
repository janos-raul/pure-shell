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
import 'package:pureshell/core/keys/keystore_api.dart';
import 'package:pureshell/core/lock/app_lock_controller.dart';
import 'package:pureshell/core/lock/app_lock_settings.dart';
import 'package:pureshell/core/ssh/session_keeper.dart';
import 'package:pureshell/core/storage/screenshot_settings.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/settings/settings_screen.dart';
import 'package:pureshell/ui/theme.dart';

import 'fake_keystore.dart';

class _NoWindow implements WindowSecurity {
  @override
  Future<void> setSecure(bool secure) async {}
}

/// An option in the open dialog (the row values behind it can read the same).
Finder inDialog(String text) =>
    find.descendant(of: find.byType(SimpleDialog), matching: find.text(text));

void main() {
  late MemorySecureStore store;
  late AppLockController lock;
  late ScreenshotSettings shots;
  late TerminalSettings terminal;

  Future<void> pump(WidgetTester t) async {
    PromptTracker.active.value = 0;
    store = MemorySecureStore();
    lock = AppLockController(FakeKeystore(), AppLockSettings(store));
    await lock.init();
    shots = ScreenshotSettings(store, _NoWindow());
    await shots.init();
    terminal = TerminalSettings(store);
    await t.pumpWidget(
      MaterialApp(
        theme: pureShellTheme(),
        home: SettingsScreen(
          lock: lock,
          screenshots: shots,
          terminal: terminal,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('sections, and each row shows its current value', (t) async {
    await pump(t);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
    for (final title in [
      'App lock',
      'Lock after',
      'Allow screenshots',
      'Input mode',
      'Terminal colors',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('1 minute'), findsOneWidget);
    expect(find.text('Direct (key by key)'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    // No inline dropdowns or switches.
    expect(find.byType(DropdownButton<InputMode>), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('a row opens a dialog with an explanation per option', (t) async {
    await pump(t);
    await t.tap(find.text('Input mode'));
    await t.pumpAndSettle();
    expect(find.text('Composing (IME words)'), findsOneWidget);
    expect(
      find.text('Every character is sent as soon as it is typed.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsOneWidget); // the current one
    await t.tap(find.text('Composing (IME words)'));
    await t.pumpAndSettle();
    expect(find.text('Composing (IME words)'), findsOneWidget); // row value
    expect(await terminal.loadInputMode(), InputMode.composing);
  });

  testWidgets('terminal colors and screenshots are stored', (t) async {
    t.view.physicalSize = const Size(1080, 3000);
    addTearDown(t.view.resetPhysicalSize);
    await pump(t);
    await t.tap(find.text('Terminal colors'));
    await t.pumpAndSettle();
    await t.tap(find.text('Phosphor green'));
    await t.pumpAndSettle();
    expect(await terminal.loadColors(), TerminalColors.phosphor);

    await t.tap(find.text('Allow screenshots'));
    await t.pumpAndSettle();
    await t.tap(inDialog('On'));
    await t.pumpAndSettle();
    expect(shots.allowed, isTrue);
  });

  testWidgets('lock after follows app lock, and a dismissed dialog changes '
      'nothing', (t) async {
    await pump(t);
    await t.tap(find.text('Lock after'));
    await t.pumpAndSettle();
    await t.tap(find.text('5 minutes'));
    await t.pumpAndSettle();
    expect(lock.timeout, LockTimeout.fiveMinutes);

    await t.tap(find.text('App lock'));
    await t.pumpAndSettle();
    await t.tap(inDialog('Off'));
    await t.pumpAndSettle();
    expect(lock.enabled, isFalse);
    // With the lock off, "Lock after" does nothing.
    await t.tap(find.text('Lock after'));
    await t.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);

    await t.tap(find.text('Allow screenshots'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(5, 5)); // outside the dialog
    await t.pumpAndSettle();
    expect(shots.allowed, isFalse);
  });

  test('UI text is proportional, technical values are monospace', () {
    expect(
      pureShellTheme().textTheme.bodyMedium?.fontFamily,
      isNot('monospace'),
    );
    expect(monoStyle.fontFamily, 'monospace');
  });

  testWidgets('Connection: keep sessions alive is on by default and saved', (
    t,
  ) async {
    await pump(t);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Keep sessions alive'), findsOneWidget);
    expect(await terminal.loadKeepSessions(), isTrue);

    await t.tap(find.text('Keep sessions alive'));
    await t.pumpAndSettle();
    await t.tap(inDialog('Off'));
    await t.pumpAndSettle();
    expect(await terminal.loadKeepSessions(), isFalse);
    expect(SessionKeeper.instance.enabled, isFalse);

    await t.tap(find.text('Keep sessions alive'));
    await t.pumpAndSettle();
    await t.tap(inDialog('On'));
    await t.pumpAndSettle();
    expect(await terminal.loadKeepSessions(), isTrue);
    expect(SessionKeeper.instance.enabled, isTrue);
  });
}
