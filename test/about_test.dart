// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/app_info.dart';
import 'package:pureshell/core/hosts/host_repository.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/keys/key_repository.dart';
import 'package:pureshell/core/keys/key_service.dart';
import 'package:pureshell/core/lock/app_lock_controller.dart';
import 'package:pureshell/core/lock/app_lock_settings.dart';
import 'package:pureshell/core/storage/screenshot_settings.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/about_screen.dart';
import 'package:pureshell/ui/hosts/host_list_screen.dart';
import 'package:pureshell/ui/settings/settings_screen.dart';
import 'package:pureshell/ui/theme.dart';

import 'fake_keystore.dart';

class _Window implements WindowSecurity {
  @override
  Future<void> setSecure(bool secure) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/app_info');

  void mockVersion(Object? reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => reply);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }

  Future<void> pumpAbout(WidgetTester t) async {
    // Tall, so the lazy list builds everything.
    t.view.physicalSize = const Size(1080, 6000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: pureShellTheme(),
        home: AboutScreen(appInfo: AppInfo(channel: channel)),
      ),
    );
    await t.pumpAndSettle();
  }

  group('app version', () {
    test('read from the native side', () async {
      mockVersion({'name': '1.0.0', 'build': '8'});
      final v = await AppInfo(channel: channel).version();
      expect(v!.name, '1.0.0');
      expect(v.build, '8');
      expect(v.toString(), 'Version 1.0.0 (8)');
    });

    test('null without a native side or with a broken answer', () async {
      expect(await AppInfo(channel: channel).version(), isNull);
      mockVersion({'name': '1.0.0'});
      expect(await AppInfo(channel: channel).version(), isNull);
    });
  });

  group('about screen', () {
    testWidgets('shows version, license, source and copyright', (t) async {
      mockVersion({'name': '1.0.0', 'build': '8'});
      await pumpAbout(t);
      expect(find.text('Version 1.0.0 (8)'), findsOneWidget);
      expect(
        find.textContaining('GNU General Public License, version 3 or later'),
        findsOneWidget,
      );
      expect(find.text(sourceUrl), findsOneWidget);
      expect(find.text('Copyright (C) 2026 Janos-Raul'), findsOneWidget);
    });

    testWidgets('without a version it says so instead of guessing', (t) async {
      await pumpAbout(t);
      expect(find.text('Version unknown'), findsOneWidget);
    });

    testWidgets('the xterm fork note points at docs/xterm-fork.md', (t) async {
      mockVersion({'name': '1.0.0', 'build': '8'});
      await pumpAbout(t);
      expect(find.textContaining('fork of xterm.dart (MIT license)'), findsOne);
      expect(
        find.textContaining('described in docs/xterm-fork.md'),
        findsOneWidget,
      );
      expect(find.text(xtermForkDocUrl), findsOneWidget);
      expect(find.text(xtermForkUrl), findsOneWidget);
      // The document it points to is really in the source.
      expect(File('docs/xterm-fork.md').existsSync(), isTrue);
      expect(xtermForkDocUrl, endsWith('docs/xterm-fork.md'));
    });

    testWidgets('links are copyable text, not buttons that open a browser', (
      t,
    ) async {
      mockVersion({'name': '1.0.0', 'build': '8'});
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpAbout(t);
      final source = t.widget<SelectableText>(
        find.widgetWithText(SelectableText, sourceUrl),
      );
      expect(source.style?.fontFamily, 'monospace');
      await t.tap(find.byTooltip('Copy link').first);
      await t.pump();
      expect(copied, sourceUrl);
    });

    testWidgets('the open-source licenses page is one tap away', (t) async {
      mockVersion({'name': '1.0.0', 'build': '8'});
      await pumpAbout(t);
      await t.scrollUntilVisible(
        find.text('Open-source licenses'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Open-source licenses'));
      await t.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
    });
  });

  group('how to reach it', () {
    testWidgets('from the host list menu', (t) async {
      final store = MemorySecureStore();
      final keystore = FakeKeystore();
      await t.pumpWidget(
        MaterialApp(
          theme: pureShellTheme(),
          home: HostListScreen(
            hosts: HostRepository(store),
            knownHosts: KnownHostsStore(store),
            settings: TerminalSettings(store),
            keyService: KeyService(keystore, KeyRepository(store)),
            lock: AppLockController(keystore, AppLockSettings(store)),
            screenshots: ScreenshotSettings(store, _Window()),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      expect(
        [
          for (final w in t.widgetList<PopupMenuItem<String>>(
            find.byType(PopupMenuItem<String>),
          ))
            w.value,
        ],
        ['keys', 'settings', 'help', 'about'],
      );
      await t.tap(find.text('About'));
      await t.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
    });

    testWidgets('from a row at the bottom of Settings', (t) async {
      final store = MemorySecureStore();
      final lock = AppLockController(FakeKeystore(), AppLockSettings(store));
      await lock.init();
      final shots = ScreenshotSettings(store, _Window());
      await shots.init();
      await t.pumpWidget(
        MaterialApp(
          theme: pureShellTheme(),
          home: SettingsScreen(
            lock: lock,
            screenshots: shots,
            terminal: TerminalSettings(store),
          ),
        ),
      );
      await t.pumpAndSettle();
      // (Tall screen: the row would otherwise sit at the very edge.)
      t.view.physicalSize = const Size(1080, 4000);
      addTearDown(t.view.reset);
      await t.pumpAndSettle();
      await t.tap(find.text('About Pure-Shell'));
      await t.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
    });
  });
}
