// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/host_repository.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/keys/key_repository.dart';
import 'package:pureshell/core/keys/key_service.dart';
import 'package:pureshell/core/keys/ssh_ec_encoding.dart' show ecdsaP256Type;
import 'package:pureshell/core/keys/ssh_ed25519_encoding.dart' show ed25519Type;
import 'package:pureshell/core/lock/app_lock_controller.dart';
import 'package:pureshell/core/lock/app_lock_settings.dart';
import 'package:pureshell/core/ssh/keep_alive.dart';
import 'package:pureshell/core/storage/screenshot_settings.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/command_block.dart';
import 'package:pureshell/ui/help/help_content.dart';
import 'package:pureshell/ui/help/help_screen.dart';
import 'package:pureshell/ui/hosts/host_key_mismatch_screen.dart';
import 'package:pureshell/ui/hosts/host_list_screen.dart';
import 'package:pureshell/ui/keys/key_detail_screen.dart';
import 'package:pureshell/ui/terminal/terminal_clipboard.dart';
import 'package:pureshell/ui/theme.dart';

import 'fake_keystore.dart';

class _Window implements WindowSecurity {
  @override
  Future<void> setSecure(bool secure) async {}
}

/// All text of a topic, for checks.
String _all(HelpTopic t) => [
  for (final b in t.blocks)
    switch (b) {
      HelpHeading() => b.text,
      HelpText() => b.text,
      HelpSteps() => b.steps.join('\n'),
      HelpCommand() => b.command,
    },
].join('\n');

void main() {
  group('markup', () {
    test('code and bold become spans, the rest stays plain', () {
      final spans = helpSpans('a `b` c **d** e');
      final texts = [for (final s in spans) (s as TextSpan).text];
      expect(texts, ['a ', 'b', ' c ', 'd', ' e']);
      expect((spans[1] as TextSpan).style?.fontFamily, 'monospace');
      expect((spans[3] as TextSpan).style?.fontWeight, FontWeight.bold);
    });

    test('text without markup is one span', () {
      expect(helpSpans('plain').length, 1);
    });
  });

  group('content', () {
    test('every topic is there, with a unique id and some text', () {
      expect(
        [for (final t in helpTopics) t.title],
        [
          'Adding a key to a server',
          'The first connection and host keys',
          'Direct and Composing input',
          'The command box',
          'Copy and paste',
          'Keeping sessions alive',
          'Long-running jobs: tmux',
          'Keys can be lost',
        ],
      );
      expect({for (final t in helpTopics) t.id}.length, helpTopics.length);
      for (final t in helpTopics) {
        expect(t.blocks, isNotEmpty);
        expect(_all(t).trim(), isNotEmpty);
      }
    });

    test(
      'keys are ECDSA: the copied line starts with ecdsa-sha2-nistp256',
      () async {
        final text = _all(helpTopicById(helpAddKey)!);
        expect(text, contains(ecdsaP256Type));
        expect(text, contains(ed25519Type)); // software keys only
        expect(
          text.indexOf(ecdsaP256Type),
          lessThan(text.indexOf(ed25519Type)),
        );

        // ... and it is what the app really copies for a hardware key.
        final service = KeyService(
          FakeKeystore(),
          KeyRepository(MemorySecureStore()),
          random: Random(1),
        );
        final key = await service.generate(name: 'k', comment: 'c');
        expect(key.isSoftware, isFalse);
        expect(key.authorizedKeysLine, startsWith('$ecdsaP256Type '));
      },
    );

    test('the from= example is a subnet and mentions the LAN address', () {
      final text = _all(helpTopicById(helpAddKey)!);
      expect(text, contains('from="192.168.1.0/24"'));
      expect(text, contains("phone's address on the local network"));
      expect(text, contains('mobile data'));
    });

    test('the first-connect text says nothing is sent on a mismatch', () {
      final text = _all(helpTopicById(helpFirstConnect)!);
      expect(text, contains('Nothing is sent to the server'));
      expect(text, contains('Remove trusted key'));
      expect(
        text,
        contains('ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'),
      );
    });

    test('the keep-alive text matches the ping interval', () {
      final text = _all(helpTopics.firstWhere((t) => t.id == 'keep-alive'));
      expect(keepAliveInterval.inSeconds, 30);
      expect(text, contains('every ${keepAliveInterval.inSeconds} seconds'));
    });

    test('pasted text: what the help says is what sanitizePaste does', () {
      final text = _all(helpTopics.firstWhere((t) => t.id == 'copy-paste'));
      expect(text, contains('Escape included'));
      expect(text, contains('except tabs and line breaks'));
      // Escape and other control characters go; tab and line breaks stay.
      expect(sanitizePaste('a\x1bb\x03c\td\ne'), 'abc\td\re');
    });

    test('every button the help mentions exists in the app', () {
      const labels = [
        'Keep sessions alive',
        'Remove trusted key',
        'Disconnect all',
        'Keep open',
        'Input mode',
        'Select all',
        'Trust',
        'Paste',
        'Copy',
        'Send',
        'Keys',
      ];
      final source = StringBuffer();
      for (final dir in ['lib/ui', 'android/app/src/main/kotlin']) {
        for (final f in Directory(dir).listSync(recursive: true)) {
          if (f is File &&
              (f.path.endsWith('.dart') || f.path.endsWith('.kt')) &&
              !f.path.contains('help_content')) {
            source.write(f.readAsStringSync());
          }
        }
      }
      final text = source.toString();
      for (final l in labels) {
        expect(
          text.contains("'$l'") || text.contains('"$l"'),
          isTrue,
          reason: 'no "$l" in the app',
        );
      }
    });
  });

  group('screens', () {
    testWidgets('the list shows every topic and opens it', (t) async {
      await t.pumpWidget(
        MaterialApp(theme: pureShellTheme(), home: const HelpScreen()),
      );
      for (final topic in helpTopics) {
        await t.scrollUntilVisible(find.text(topic.title), 80);
        expect(find.text(topic.title), findsOneWidget);
      }
      await t.scrollUntilVisible(find.text('Adding a key to a server'), -80);
      await t.tap(find.text('Adding a key to a server'));
      await t.pumpAndSettle();
      expect(find.byType(HelpTopicScreen), findsOneWidget);
      expect(find.textContaining('never leaves it'), findsOneWidget);
    });

    testWidgets('every topic renders on a small phone without errors', (
      t,
    ) async {
      // 360 dp wide like a small phone; tall so the lazy list builds everything.
      t.view.physicalSize = const Size(720, 8000);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      for (final topic in helpTopics) {
        await t.pumpWidget(
          MaterialApp(
            theme: pureShellTheme(),
            home: HelpTopicScreen(topic: topic),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: topic.title);
        // Commands are monospace and copyable.
        final commands = topic.blocks.whereType<HelpCommand>().length;
        expect(
          find.byType(CommandBlock, skipOffstage: false),
          findsNWidgets(commands),
        );
      }
    });

    testWidgets('the host list menu opens Help', (t) async {
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
      await t.tap(find.text('Help'));
      await t.pumpAndSettle();
      expect(find.byType(HelpScreen), findsOneWidget);
    });

    testWidgets('the mismatch screen links to the first-connection topic', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          theme: pureShellTheme(),
          home: const HostKeyMismatchScreen(
            host: Host(
              id: '1',
              label: 'x',
              hostname: 'example.com',
              username: 'u',
            ),
            stored: HostKey(type: 'ssh-ed25519', fingerprint: 'SHA256:a'),
            presented: HostKey(type: 'ssh-ed25519', fingerprint: 'SHA256:b'),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Why is this blocked?'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Why is this blocked?'));
      await t.pumpAndSettle();
      expect(find.byType(HelpTopicScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('The first connection and host keys'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the key detail links to adding a key to a server', (t) async {
      final service = KeyService(
        FakeKeystore(),
        KeyRepository(MemorySecureStore()),
        random: Random(1),
      );
      final key = await service.generate(name: 'Phone', comment: 'c');
      await t.pumpWidget(
        MaterialApp(
          theme: pureShellTheme(),
          home: KeyDetailScreen(keyService: service, sshKey: key),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('How to add this key to a server'));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Adding a key to a server'),
        ),
        findsOneWidget,
      );
    });
  });
}
