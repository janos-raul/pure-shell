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
import 'package:pureshell/ui/hosts/host_list_screen.dart';

import 'fake_keystore.dart';

class _Window implements WindowSecurity {
  @override
  Future<void> setSecure(bool secure) async {}
}

void main() {
  testWidgets('each host shows its login method; label proportional, '
      'address monospace', (t) async {
    final store = MemorySecureStore();
    final hosts = HostRepository(store);
    await hosts.upsert(
      const Host(
        id: '1',
        label: 'Web server',
        hostname: 'example.com',
        username: 'deploy',
        port: 2222,
        authMethod: AuthMethod.key,
        keyId: 'k',
      ),
    );
    await hosts.upsert(
      const Host(
        id: '2',
        label: 'Backup',
        hostname: '192.0.2.7',
        username: 'root',
      ),
    );
    final keystore = FakeKeystore();
    await t.pumpWidget(
      MaterialApp(
        home: HostListScreen(
          hosts: hosts,
          knownHosts: KnownHostsStore(store),
          settings: TerminalSettings(store),
          keyService: KeyService(keystore, KeyRepository(store)),
          lock: AppLockController(keystore, AppLockSettings(store)),
          screenshots: ScreenshotSettings(store, _Window()),
        ),
      ),
    );
    await t.pumpAndSettle();

    Finder row(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(ListTile));
    expect(
      find.descendant(
        of: row('Web server'),
        matching: find.byIcon(Icons.vpn_key),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('Backup'), matching: find.byIcon(Icons.password)),
      findsOneWidget,
    );

    // Label: the theme's proportional font. Address: monospace.
    expect(t.widget<Text>(find.text('Web server')).style?.fontFamily, isNull);
    final address = t.widget<Text>(find.text('deploy@example.com:2222'));
    expect(address.style?.fontFamily, 'monospace');
  });
}
