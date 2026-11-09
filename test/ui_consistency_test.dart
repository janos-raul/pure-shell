// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/host_key_command.dart';
import 'package:pureshell/core/hosts/host_repository.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/keys/key_repository.dart';
import 'package:pureshell/core/keys/key_service.dart';
import 'package:pureshell/core/lock/app_lock_controller.dart';
import 'package:pureshell/core/lock/app_lock_settings.dart';
import 'package:pureshell/core/storage/screenshot_settings.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/command_block.dart';
import 'package:pureshell/ui/hosts/connect_flow.dart';
import 'package:pureshell/ui/hosts/host_edit_screen.dart';
import 'package:pureshell/ui/hosts/host_key_mismatch_screen.dart';
import 'package:pureshell/ui/hosts/host_list_screen.dart';
import 'package:pureshell/ui/keys/key_detail_screen.dart';
import 'package:pureshell/ui/keys/keys_screen.dart';
import 'package:pureshell/ui/theme.dart';

import 'fake_keystore.dart';

class _Window implements WindowSecurity {
  @override
  Future<void> setSecure(bool secure) async {}
}

const _keyHost = Host(
  id: '1',
  label: 'Web',
  hostname: 'example.com',
  username: 'deploy',
  authMethod: AuthMethod.key,
  keyId: 'k',
);
const _pwHost = Host(
  id: '2',
  label: 'Backup',
  hostname: '192.0.2.7',
  username: 'root',
);
const _old = HostKey(type: 'ssh-ed25519', fingerprint: 'SHA256:old');
const _new = HostKey(type: 'ecdsa-sha2-nistp256', fingerprint: 'SHA256:new');

void main() {
  group('host key check command', () {
    test('names the host key file of the key type', () {
      expect(
        hostKeyCheckCommand('ssh-ed25519'),
        'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub',
      );
      expect(
        hostKeyCheckCommand('ssh-rsa'),
        'ssh-keygen -lf /etc/ssh/ssh_host_rsa_key.pub',
      );
      for (final t in [
        'ecdsa-sha2-nistp256',
        'ecdsa-sha2-nistp384',
        'ecdsa-sha2-nistp521',
      ]) {
        expect(
          hostKeyCheckCommand(t),
          'ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub',
        );
      }
    });

    test('an unknown type lists all host keys', () {
      expect(
        hostKeyCheckCommand('something-new'),
        'ssh-keygen -lf /etc/ssh/ssh_host_*_key.pub',
      );
      expect(
        hostKeyCheckCommand(''),
        'ssh-keygen -lf /etc/ssh/ssh_host_*_key.pub',
      );
    });
  });

  group('first-connect prompt', () {
    testWidgets('shows the exact command for the key type, copyable', (
      t,
    ) async {
      final store = MemorySecureStore();
      final controller = ConnectController(
        host: _pwHost,
        knownHosts: KnownHostsStore(store),
      );
      controller.askTrust(_new, Completer<void>().future);
      await t.pumpWidget(
        MaterialApp(
          theme: pureShellTheme(),
          home: ConnectDialog(
            controller: controller,
            host: _pwHost,
            onCancel: () {},
            onReconnect: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(CommandBlock), findsOneWidget);
      final cmd = t.widget<SelectableText>(
        find.descendant(
          of: find.byType(CommandBlock),
          matching: find.byType(SelectableText),
        ),
      );
      expect(cmd.data, 'ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub');
      expect(cmd.style?.fontFamily, 'monospace');
      expect(find.byTooltip('Copy command'), findsOneWidget);
      controller.dispose();
    });
  });

  group('host key mismatch', () {
    Future<void> pump(WidgetTester t, Host host) async {
      await t.pumpWidget(
        MaterialApp(
          theme: pureShellTheme(),
          home: HostKeyMismatchScreen(
            host: host,
            stored: _old,
            presented: _new,
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('a key host: nothing was sent to the server', (t) async {
      await pump(t, _keyHost);
      expect(find.textContaining('Nothing was sent to the server.'), findsOne);
      expect(find.textContaining('No password was sent'), findsNothing);
    });

    testWidgets('a password host: no password was sent', (t) async {
      await pump(t, _pwHost);
      expect(find.textContaining('No password was sent.'), findsOneWidget);
    });

    testWidgets('shows the command for the presented key type', (t) async {
      await pump(t, _pwHost);
      expect(
        find.text('ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub'),
        findsOneWidget,
      );
    });

    testWidgets('no way to accept the new key, only Back', (t) async {
      await pump(t, _keyHost);
      expect(find.text('Trust'), findsNothing);
      expect(find.textContaining('Accept'), findsNothing);
      expect(find.textContaining('Continue'), findsNothing);
      // (Scrolled out of the small test screen, so look off-screen too.)
      expect(find.byType(FilledButton, skipOffstage: false), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Back', skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  group('create key dialog', () {
    late KeyService service;
    setUp(() {
      service = KeyService(
        FakeKeystore(),
        KeyRepository(MemorySecureStore()),
        random: Random(1),
      );
    });

    testWidgets('Required only after Create is tapped with an empty name', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          theme: pureShellTheme(),
          home: KeysScreen(keyService: service),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();
      await t.tap(find.text('I understand'));
      await t.pumpAndSettle();

      expect(find.text('Required'), findsNothing); // not when it opens
      await t.tap(find.text('Create'));
      await t.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextFormField, 'Name'), 'x');
      await t.pumpAndSettle();
      expect(find.text('Required'), findsNothing); // follows the typing
    });

    testWidgets('the helper texts fit (not cut off)', (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: pureShellTheme(),
          home: KeysScreen(keyService: service),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();
      await t.tap(find.text('I understand'));
      await t.pumpAndSettle();
      expect(
        find.text('Nothing personal is added unless you type it.'),
        findsOneWidget,
      );
      // Two lines allowed: it used to be cut off with an ellipsis.
      final comment = t.widget<TextField>(
        find.widgetWithText(TextField, 'Comment (shown on servers)'),
      );
      expect(comment.decoration!.helperMaxLines, 2);
    });
  });

  group('key detail', () {
    testWidgets('Save is in the app bar and only with changes', (t) async {
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
      Finder save() =>
          find.descendant(of: find.byType(AppBar), matching: find.text('Save'));
      expect(save(), findsNothing);

      await t.enterText(find.widgetWithText(TextFormField, 'Name'), 'Phone 2');
      await t.pump();
      expect(save(), findsOneWidget);
      await t.tap(save());
      await t.pumpAndSettle();
      expect((await service.get(key.id))!.name, 'Phone 2');
      expect(save(), findsNothing);
    });
  });

  group('host edit', () {
    testWidgets('hostname: hint, and user@ is refused', (t) async {
      final store = MemorySecureStore();
      final service = KeyService(
        FakeKeystore(),
        KeyRepository(store),
        random: Random(1),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: pureShellTheme(),
          home: HostEditScreen(
            hosts: HostRepository(store),
            knownHosts: KnownHostsStore(store),
            keyService: service,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Name or address only, without user@'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextFormField, 'Label'), 'x');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Hostname'),
        'me@example.com',
      );
      await t.enterText(find.widgetWithText(TextFormField, 'Username'), 'me');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Put the username in the Username field'), findsOne);
      expect(await HostRepository(store).list(), isEmpty);
    });
  });

  group('host list menu', () {
    testWidgets('one menu with Keys and Settings, no icons in the bar', (
      t,
    ) async {
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
      final bar = find.byType(AppBar);
      expect(
        find.descendant(of: bar, matching: find.byIcon(Icons.settings)),
        findsNothing,
      );
      expect(
        find.descendant(of: bar, matching: find.byIcon(Icons.vpn_key)),
        findsNothing,
      );
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      expect(find.text('Keys'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      await t.tap(find.text('Keys'));
      await t.pumpAndSettle();
      expect(find.byType(KeysScreen), findsOneWidget);
    });
  });

  group('one green fill', () {
    test('a selected segment uses the same green as buttons', () {
      final theme = pureShellTheme();
      final selected = theme.segmentedButtonTheme.style!.backgroundColor!
          .resolve({WidgetState.selected});
      expect(selected, theme.colorScheme.primary);
    });

    test('a switch that is off does not look like one that is on', () {
      final s = pureShellTheme().switchTheme;
      final on = s.thumbColor!.resolve({WidgetState.selected});
      final off = s.thumbColor!.resolve({});
      expect(on, isNot(off));
      expect(
        s.trackColor!.resolve({WidgetState.selected}),
        isNot(s.trackColor!.resolve({})),
      );
    });
  });

  group('dialog buttons', () {
    test(
      'the main action of a dialog is a filled button, never plain text',
      () {
        // One filled main action; Cancel and friends stay text; destructive
        // actions are red text. These labels are always a dialog's main action.
        final banned = RegExp(
          r"TextButton\((?:(?!Button\().)*?child:\s*(?:const\s+)?Text\('(OK|Connect|Continue|Paste|Disconnect|Unlock)'\)",
          dotAll: true,
        );
        final offenders = <String>[];
        for (final f in Directory('lib').listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          for (final m in banned.allMatches(f.readAsStringSync())) {
            offenders.add('${f.path}: ${m.group(1)}');
          }
        }
        expect(offenders, isEmpty, reason: offenders.join('\n'));
      },
    );
  });
}
