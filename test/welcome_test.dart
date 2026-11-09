// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/host_repository.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/keys/key_repository.dart';
import 'package:pureshell/core/keys/key_service.dart';
import 'package:pureshell/core/lock/app_lock_controller.dart';
import 'package:pureshell/core/lock/app_lock_settings.dart';
import 'package:pureshell/core/storage/screenshot_settings.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/help/help_screen.dart';
import 'package:pureshell/ui/hosts/host_edit_screen.dart';
import 'package:pureshell/ui/hosts/host_list_screen.dart';
import 'package:pureshell/ui/keys/keys_screen.dart';
import 'package:pureshell/ui/theme.dart';

import 'fake_keystore.dart';

class _Window implements WindowSecurity {
  @override
  Future<void> setSecure(bool secure) async {}
}

void main() {
  late MemorySecureStore store;
  late FakeKeystore keystore;
  late KeyService keyService;

  setUp(() {
    store = MemorySecureStore();
    keystore = FakeKeystore();
    keyService = KeyService(keystore, KeyRepository(store), random: Random(1));
  });

  Future<void> pumpList(WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: pureShellTheme(),
        home: HostListScreen(
          hosts: HostRepository(store),
          knownHosts: KnownHostsStore(store),
          settings: TerminalSettings(store),
          keyService: keyService,
          lock: AppLockController(keystore, AppLockSettings(store)),
          screenshots: ScreenshotSettings(store, _Window()),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('no hosts: a short welcome with both ways to start', (t) async {
    await pumpList(t);
    expect(find.text('Welcome to PureShell'), findsOneWidget);
    expect(find.text('>_'), findsOneWidget);
    expect(find.textContaining('saved on this phone only'), findsOneWidget);
    expect(find.textContaining('can never leave it'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add a host'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Create a key'), findsOneWidget);
    expect(find.text('How it works'), findsOneWidget);
    // The old one-liner is gone.
    expect(find.textContaining('No hosts yet'), findsNothing);
  });

  testWidgets('Add a host opens the host form', (t) async {
    await pumpList(t);
    await t.tap(find.text('Add a host'));
    await t.pumpAndSettle();
    expect(find.byType(HostEditScreen), findsOneWidget);
  });

  testWidgets('Create a key goes straight into creating one', (t) async {
    await pumpList(t);
    await t.tap(find.text('Create a key'));
    await t.pumpAndSettle();
    expect(find.byType(KeysScreen), findsOneWidget);
    expect(find.text('Keys can be lost'), findsOneWidget); // before the first
    await t.tap(find.text('I understand'));
    await t.pumpAndSettle();
    expect(find.text('Create key'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextFormField, 'Name'), 'Phone');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();
    expect((await keyService.list()).single.name, 'Phone');

    // Back on the welcome: a key exists, so it is not offered again.
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Welcome to PureShell'), findsOneWidget);
    expect(find.text('Create a key'), findsNothing);
    expect(find.text('Add a host'), findsOneWidget);
  });

  testWidgets('with a key already made, only Add a host and the link', (
    t,
  ) async {
    await keyService.generate(name: 'Phone', comment: 'c');
    await pumpList(t);
    expect(find.text('Create a key'), findsNothing);
    expect(find.text('Add a host'), findsOneWidget);
    expect(find.text('How it works'), findsOneWidget);
  });

  testWidgets('How it works opens the help', (t) async {
    await pumpList(t);
    await t.tap(find.text('How it works'));
    await t.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
  });

  testWidgets('with hosts there is no welcome', (t) async {
    await HostRepository(store).upsert(
      const Host(id: '1', label: 'Web', hostname: 'example.com', username: 'u'),
    );
    await pumpList(t);
    expect(find.text('Welcome to PureShell'), findsNothing);
    expect(find.text('Web'), findsOneWidget);
  });

  testWidgets('fits a small phone, and scrolls in landscape', (t) async {
    addTearDown(t.view.reset);
    t.view.devicePixelRatio = 2;
    for (final size in [const Size(720, 1280), const Size(1280, 720)]) {
      t.view.physicalSize = size;
      await pumpList(t);
      expect(t.takeException(), isNull, reason: '$size');
      await t.ensureVisible(find.text('How it works'));
      await t.pumpAndSettle();
      expect(find.text('How it works'), findsOneWidget);
    }
  });
}
