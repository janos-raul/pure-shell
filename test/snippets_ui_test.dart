// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/keys/keystore_api.dart';
import 'package:pureshell/core/lock/app_lock_controller.dart';
import 'package:pureshell/core/lock/app_lock_settings.dart';
import 'package:pureshell/core/snippets/snippet.dart';
import 'package:pureshell/core/snippets/snippet_repository.dart';
import 'package:pureshell/core/ssh/ssh_connection.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/lock/app_lock_gate.dart';
import 'package:pureshell/ui/snippets/snippet_edit_screen.dart';
import 'package:pureshell/ui/snippets/snippets_screen.dart';
import 'package:pureshell/ui/terminal/direct_input.dart';
import 'package:pureshell/ui/terminal/terminal_screen.dart';

import 'fake_keystore.dart';

const _host = Host(
  id: 'h1',
  label: 'Test',
  hostname: 'example.com',
  username: 'u',
);

class _FakeSession implements SSHSession {
  final stdinData = StreamController<Uint8List>();
  final doneC = Completer<void>();
  final sent = <int>[];

  _FakeSession() {
    stdinData.stream.listen(sent.addAll);
  }

  @override
  StreamSink<Uint8List> get stdin => stdinData.sink;
  @override
  Stream<Uint8List> get stdout => const Stream.empty();
  @override
  Stream<Uint8List> get stderr => const Stream.empty();
  @override
  Future<void> get done => doneC.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Connection extends SshConnection {
  _Connection(MemorySecureStore store)
    : super(
        host: _host,
        knownHosts: KnownHostsStore(store),
        onTrustPrompt: (key, closed) async => true,
      );

  _FakeSession? fake;

  @override
  SSHSession? get session => fake;

  @override
  Future<SSHSession> openShell(int columns, int rows) async =>
      fake = _FakeSession();

  @override
  void resize(int columns, int rows) {}

  @override
  void close() {}
}

Snippet _s(
  String id, {
  String? host,
  String text = 'uptime',
  SnippetMode mode = SnippetMode.run,
  bool confirm = false,
}) => Snippet(
  id: id,
  name: 'name-$id',
  text: text,
  hostId: host,
  mode: mode,
  confirm: confirm,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Connection conn;
  late SnippetRepository repo;

  Future<void> pumpScreen(
    WidgetTester t, {
    List<Snippet> seed = const [],
  }) async {
    PromptTracker.active.value = 0;
    final store = MemorySecureStore();
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(DirectInput.channelName),
      (call) async => null,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(DirectInput.channelName),
        null,
      ),
    );
    repo = SnippetRepository(store);
    for (final s in seed) {
      await repo.upsert(s);
    }
    conn = _Connection(store);
    final lock = AppLockController(FakeKeystore(), AppLockSettings(store));
    await lock.init();
    if (lock.locked) await lock.unlock();
    await t.pumpWidget(
      MaterialApp(
        home: AppLockScope(
          controller: lock,
          child: TerminalScreen(
            host: _host,
            connection: conn,
            settings: TerminalSettings(store),
            snippets: repo,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  String serverGot() => utf8.decode(conn.fake!.sent);
  final snippetsKey = find.byIcon(Icons.bookmarks_outlined);
  final boxField = find.byKey(const ValueKey('command-box-field'));

  Future<void> openSheet(WidgetTester t) async {
    await t.tap(snippetsKey);
    await t.pumpAndSettle();
  }

  group('session screen', () {
    testWidgets('the list shows this host first, then the global ones', (
      t,
    ) async {
      await pumpScreen(
        t,
        seed: [
          _s('g1'),
          _s('other', host: 'h2'),
          _s('h1a', host: 'h1'),
          _s('g2'),
        ],
      );
      await openSheet(t);
      expect(find.text('name-other'), findsNothing);
      final ys = [
        for (final id in ['h1a', 'g1', 'g2'])
          t.getTopLeft(find.text('name-$id')).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(find.text('Manage snippets'), findsOneWidget);
    });

    testWidgets('an empty list says so and offers Manage', (t) async {
      await pumpScreen(t);
      await openSheet(t);
      expect(find.textContaining('No snippets yet'), findsOneWidget);
      expect(find.text('Manage snippets'), findsOneWidget);
    });

    testWidgets('run: one line is sent with Enter', (t) async {
      await pumpScreen(t, seed: [_s('a', text: 'uptime')]);
      await openSheet(t);
      await t.tap(find.text('name-a'));
      await t.pumpAndSettle();
      expect(serverGot(), 'uptime\r');
    });

    testWidgets('run: several lines go in as a paste, then Enter, no '
        '"Paste N lines?" question', (t) async {
      await pumpScreen(t, seed: [_s('a', text: 'cd /tmp\nls')]);
      await openSheet(t);
      await t.tap(find.text('name-a'));
      await t.pumpAndSettle();
      expect(find.textContaining('Paste'), findsNothing);
      expect(serverGot(), 'cd /tmp\rls\r');
    });

    testWidgets('run with "ask before running": Cancel sends nothing, Run '
        'sends', (t) async {
      await pumpScreen(t, seed: [_s('a', text: 'rm -rf x', confirm: true)]);
      await openSheet(t);
      await t.tap(find.text('name-a'));
      await t.pumpAndSettle();
      expect(find.text('Run "name-a"?'), findsOneWidget);
      expect(find.text('rm -rf x'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(conn.fake!.sent, isEmpty);

      await openSheet(t);
      await t.tap(find.text('name-a'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Run'));
      await t.pumpAndSettle();
      expect(serverGot(), 'rm -rf x\r');
    });

    testWidgets('insert: the text lands in the command box, nothing is '
        'sent', (t) async {
      await pumpScreen(
        t,
        seed: [_s('a', text: 'ls -la', mode: SnippetMode.insert)],
      );
      await openSheet(t);
      await t.tap(find.text('name-a'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(boxField).controller!.text, 'ls -la');
      expect(conn.fake!.sent, isEmpty);
      // Send is the user's own step.
      await t.tap(find.byIcon(Icons.send));
      await t.pumpAndSettle();
      expect(serverGot(), 'ls -la\r');
    });

    testWidgets('Manage opens the manager', (t) async {
      await pumpScreen(t, seed: [_s('a')]);
      await openSheet(t);
      await t.tap(find.text('Manage snippets'));
      await t.pumpAndSettle();
      expect(find.byType(SnippetsScreen), findsOneWidget);
      expect(find.text('For Test'), findsOneWidget);
      expect(find.text('For every host'), findsOneWidget);
    });

    testWidgets('after the session ends nothing can be inserted or run', (
      t,
    ) async {
      await pumpScreen(t, seed: [_s('a')]);
      conn.fake!.doneC.complete();
      await t.pumpAndSettle();
      // The key stays usable so the reason can be shown.
      await openSheet(t);
      expect(find.byKey(const ValueKey('snippets-ended')), findsOneWidget);
      await t.tap(find.text('name-a'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(conn.fake!.sent, isEmpty);
      expect(boxField, findsNothing);
      // Manage still works.
      expect(find.text('Manage snippets'), findsOneWidget);
    });

    testWidgets('portrait: the top bar has a Snippets button too', (t) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await pumpScreen(t);
      expect(find.byKey(const ValueKey('snippets-button')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('snippets-button')));
      await t.pumpAndSettle();
      expect(find.text('Manage snippets'), findsOneWidget);
    });

    testWidgets('landscape: the pull-down bar has the button', (t) async {
      t.view.physicalSize = const Size(800, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await pumpScreen(t);
      expect(find.byKey(const ValueKey('snippets-button')), findsNothing);
      // The top edge shows the bar for a few seconds.
      await t.tapAt(const Offset(400, 3));
      await t.pump();
      expect(find.byKey(const ValueKey('snippets-button')), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('without a repository there are no Snippets buttons', (
      t,
    ) async {
      PromptTracker.active.value = 0;
      final store = MemorySecureStore();
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(DirectInput.channelName),
        (call) async => null,
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel(DirectInput.channelName),
          null,
        ),
      );
      conn = _Connection(store);
      final lock = AppLockController(FakeKeystore(), AppLockSettings(store));
      await lock.init();
      if (lock.locked) await lock.unlock();
      await t.pumpWidget(
        MaterialApp(
          home: AppLockScope(
            controller: lock,
            child: TerminalScreen(
              host: _host,
              connection: conn,
              settings: TerminalSettings(store),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(snippetsKey, findsNothing);
    });
  });

  group('editor', () {
    late MemorySecureStore store;

    Future<void> pumpEditor(
      WidgetTester t, {
      Host? host,
      Snippet? snippet,
    }) async {
      store = MemorySecureStore();
      repo = SnippetRepository(store);
      if (snippet != null) await repo.upsert(snippet);
      await t.pumpWidget(
        MaterialApp(
          home: SnippetEditScreen(snippets: repo, host: host, snippet: snippet),
        ),
      );
      await t.pumpAndSettle();
    }

    Finder field(String label) => find.widgetWithText(TextFormField, label);

    testWidgets('warns not to put secrets in snippets', (t) async {
      await pumpEditor(t);
      expect(
        find.byKey(const ValueKey('snippet-secrets-note')),
        findsOneWidget,
      );
      expect(find.textContaining("Don't put passwords"), findsOneWidget);
    });

    testWidgets('name and command are required', (t) async {
      await pumpEditor(t);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Required'), findsNWidgets(2));
      expect(await repo.list(), isEmpty);
    });

    testWidgets('saves a global snippet (no host given), insert by default', (
      t,
    ) async {
      await pumpEditor(t);
      await t.enterText(field('Name'), '  Disk  ');
      await t.enterText(field('Command'), 'df -h\n');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final saved = (await repo.list()).single;
      expect(saved.name, 'Disk');
      expect(saved.text, 'df -h'); // no trailing line break
      expect(saved.isGlobal, isTrue);
      expect(saved.mode, SnippetMode.insert);
      expect(find.byKey(const ValueKey('snippet-host-only')), findsNothing);
    });

    testWidgets('from a host: tied to it by default, can be made global', (
      t,
    ) async {
      await pumpEditor(t, host: _host);
      expect(
        t
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('snippet-host-only')),
            )
            .value,
        isTrue,
      );
      await t.enterText(field('Name'), 'n');
      await t.enterText(field('Command'), 'ls');
      await t.tap(find.byKey(const ValueKey('snippet-host-only')));
      await t.pump();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect((await repo.list()).single.hostId, isNull);
    });

    testWidgets('"ask before running" follows the text until you touch it', (
      t,
    ) async {
      await pumpEditor(t);
      await t.tap(find.text('Run'));
      await t.pump();
      Switch confirm() => t.widget<Switch>(
        find.descendant(
          of: find.byKey(const ValueKey('snippet-confirm')),
          matching: find.byType(Switch),
        ),
      );
      expect(confirm().value, isFalse); // empty/one line: off
      await t.enterText(field('Command'), 'a\nb');
      await t.pump();
      expect(confirm().value, isTrue); // several lines: on
      await t.enterText(field('Command'), 'a');
      await t.pump();
      expect(confirm().value, isFalse); // back to one line: off again

      await t.enterText(field('Command'), 'a\nb');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('snippet-confirm')));
      await t.pump();
      expect(confirm().value, isFalse); // the user turned it off
      await t.enterText(field('Command'), 'a\nb\nc');
      await t.pump();
      expect(confirm().value, isFalse); // and it stays off
    });

    testWidgets('editing keeps the saved confirmation, however long', (
      t,
    ) async {
      await pumpEditor(t, snippet: _s('a', text: 'one line', confirm: false));
      await t.enterText(field('Command'), 'two\nlines');
      await t.pump();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect((await repo.list()).single.confirm, isFalse);
    });

    testWidgets('the confirmation switch only exists for run snippets', (
      t,
    ) async {
      await pumpEditor(t);
      expect(find.byKey(const ValueKey('snippet-confirm')), findsNothing);
      await t.tap(find.text('Run'));
      await t.pump();
      expect(find.byKey(const ValueKey('snippet-confirm')), findsOneWidget);
    });
  });

  group('manager', () {
    testWidgets('lists, deletes after a question', (t) async {
      final store = MemorySecureStore();
      repo = SnippetRepository(store);
      await repo.upsert(_s('g'));
      await repo.upsert(_s('h', host: 'h1'));
      await t.pumpWidget(
        MaterialApp(
          home: SnippetsScreen(snippets: repo, host: _host),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('name-g'), findsOneWidget);
      expect(find.text('name-h'), findsOneWidget);

      await t.tap(find.byTooltip('More').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(find.text('Delete "name-g"?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await t.pumpAndSettle();
      expect((await repo.list()).map((s) => s.id), ['h']);
    });

    testWidgets('without a host only the global list is shown', (t) async {
      final store = MemorySecureStore();
      repo = SnippetRepository(store);
      await repo.upsert(_s('g'));
      await repo.upsert(_s('h', host: 'h1'));
      await t.pumpWidget(MaterialApp(home: SnippetsScreen(snippets: repo)));
      await t.pumpAndSettle();
      expect(find.text('name-g'), findsOneWidget);
      expect(find.text('name-h'), findsNothing);
      expect(find.text('For every host'), findsOneWidget);
    });
  });
}
