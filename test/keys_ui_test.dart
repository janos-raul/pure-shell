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
import 'package:pureshell/core/keys/keystore_api.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/ui/hosts/host_edit_screen.dart';
import 'package:pureshell/ui/keys/keys_screen.dart';

import 'fake_keystore.dart';

void main() {
  late FakeKeystore keystore;
  late MemorySecureStore store;
  late KeyService service;

  setUp(() {
    keystore = FakeKeystore();
    store = MemorySecureStore();
    service = KeyService(keystore, KeyRepository(store), random: Random(1));
  });

  Future<void> openKeys(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(home: KeysScreen(keyService: service)));
    await t.pumpAndSettle();
  }

  Future<void> createKey(WidgetTester t, String name) async {
    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    if (find.text('Keys can be lost').evaluate().isNotEmpty) {
      await t.tap(find.text('I understand'));
      await t.pumpAndSettle();
    }
    await t.enterText(find.widgetWithText(TextFormField, 'Name'), name);
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();
  }

  group('key loss notice', () {
    testWidgets('shown before the first key; cancelling creates nothing and '
        'asks again', (t) async {
      await openKeys(t);
      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();
      expect(find.text('Keys can be lost'), findsOneWidget);
      expect(find.textContaining('uninstall Pure-Shell'), findsOneWidget);
      expect(find.textContaining('clear its data'), findsOneWidget);
      expect(find.textContaining('different key'), findsOneWidget);
      expect(
        find.textContaining('another way into your servers'),
        findsOneWidget,
      );
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('Create key'), findsNothing);
      expect(await service.list(), isEmpty);
      expect(await service.lossNoticeShown(), isFalse);

      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();
      expect(find.text('Keys can be lost'), findsOneWidget);
    });

    testWidgets('acknowledged once, then never again', (t) async {
      await openKeys(t);
      await createKey(t, 'first');
      expect(await service.lossNoticeShown(), isTrue);
      expect(find.text('first'), findsOneWidget);

      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();
      expect(find.text('Keys can be lost'), findsNothing);
      expect(find.text('Create key'), findsOneWidget); // straight to the name
    });

    testWidgets('no notice when the phone has no screen lock (nothing is '
        'created)', (t) async {
      keystore.secureLock = false;
      await openKeys(t);
      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();
      expect(find.text('Keys can be lost'), findsNothing);
      expect(find.text('Set a screen lock to create keys.'), findsOneWidget);
      expect(await service.lossNoticeShown(), isFalse);
    });
  });

  testWidgets('empty state explains the keys', (t) async {
    await openKeys(t);
    expect(find.textContaining('No keys yet'), findsOneWidget);
    expect(find.textContaining('never be exported'), findsOneWidget);
  });

  testWidgets('creating a key lists it with its security level badge', (
    t,
  ) async {
    await openKeys(t);
    await createKey(t, 'Phone key');
    expect(find.text('Phone key'), findsOneWidget);
    expect(find.text('TEE'), findsOneWidget);
    keystore.level = SecurityLevel.strongBox;
    await createKey(t, 'Second');
    expect(find.text('StrongBox'), findsOneWidget);
  });

  testWidgets('the comment defaults to pureshell and is editable', (t) async {
    await service.markLossNoticeShown();
    await openKeys(t);
    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'pureshell'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextFormField, 'Name'), 'k');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();
    expect((await service.list()).single.comment, 'pureshell');
  });

  testWidgets('without a screen lock: a plain message, no key dialog', (
    t,
  ) async {
    keystore.secureLock = false;
    await openKeys(t);
    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    expect(find.text('Set a screen lock to create keys.'), findsOneWidget);
    expect(find.text('Create key'), findsNothing); // no dialog
    expect(keystore.calls, isEmpty);
  });

  testWidgets('a software key is labelled as such and explained', (t) async {
    keystore.level = SecurityLevel.software;
    await openKeys(t);
    await createKey(t, 'Old phone');
    expect(find.text('Software key'), findsWidgets); // dialog title + badge
    expect(find.textContaining('no secure hardware'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.text('Software key'), findsOneWidget); // the badge
  });

  testWidgets('detail shows the public key; delete warns and removes', (
    t,
  ) async {
    await openKeys(t);
    await createKey(t, 'Phone key');
    await t.tap(find.text('Phone key'));
    await t.pumpAndSettle();
    expect(find.textContaining('ecdsa-sha2-nistp256 AAAA'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);

    await t.ensureVisible(find.text('Delete key'));
    await t.tap(find.text('Delete key'));
    await t.pumpAndSettle();
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    expect(find.textContaining('recovered or exported'), findsOneWidget);
    // Cancel keeps it.
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(await service.list(), hasLength(1));

    await t.tap(find.text('Delete key'));
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete key'),
      ),
    );
    await t.pumpAndSettle();
    expect(await service.list(), isEmpty);
    expect(keystore.ec, isEmpty);
  });

  testWidgets('the badge shows the live level when it differs from the '
      'stored one', (t) async {
    await openKeys(t);
    await createKey(t, 'Phone key'); // stored: TEE
    expect(find.text('TEE'), findsOneWidget);
    final key = (await service.list()).single;
    keystore.liveLevels[key.signAlias] = SecurityLevel.strongBox;
    await t.pumpWidget(const SizedBox()); // leave the screen
    await openKeys(t); // reopen: stored TEE, live StrongBox
    expect(find.text('StrongBox'), findsOneWidget);
    expect(find.text('TEE'), findsNothing);
  });

  group('host login settings', () {
    Future<HostRepository> openHostForm(WidgetTester t, {Host? host}) async {
      final repo = HostRepository(store);
      await t.pumpWidget(
        MaterialApp(
          home: HostEditScreen(
            hosts: repo,
            knownHosts: KnownHostsStore(store),
            keyService: service,
            host: host,
          ),
        ),
      );
      await t.pumpAndSettle();
      return repo;
    }

    testWidgets('password is the default; key choice appears on demand', (
      t,
    ) async {
      await openHostForm(t);
      expect(find.text('Key'), findsOneWidget); // the segment
      expect(find.text('Password fallback'), findsNothing);
      await t.tap(find.text('Key'));
      await t.pumpAndSettle();
      expect(find.textContaining('No keys yet'), findsOneWidget);
      final sw = find.byType(Switch);
      expect(t.widget<Switch>(sw).value, isFalse, reason: 'off by default');
    });

    testWidgets('a key host saves its key and a fallback that is off', (
      t,
    ) async {
      final key = await service.generate(name: 'Phone key');
      final repo = await openHostForm(t);
      await t.enterText(find.widgetWithText(TextFormField, 'Label'), 'srv');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Hostname'),
        'example.com',
      );
      await t.enterText(find.widgetWithText(TextFormField, 'Username'), 'u');
      await t.tap(find.text('Key'));
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Phone key').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final saved = (await repo.list()).single;
      expect(saved.authMethod, AuthMethod.key);
      expect(saved.keyId, key.id);
      expect(saved.allowPasswordFallback, isFalse);
    });

    testWidgets('key login without choosing a key is not saved', (t) async {
      await service.generate(name: 'Phone key');
      final repo = await openHostForm(t);
      await t.enterText(find.widgetWithText(TextFormField, 'Label'), 'srv');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Hostname'),
        'example.com',
      );
      await t.enterText(find.widgetWithText(TextFormField, 'Username'), 'u');
      await t.tap(find.text('Key'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.textContaining('Choose a key'), findsOneWidget);
      expect(await repo.list(), isEmpty);
    });
  });
}
