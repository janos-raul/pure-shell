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
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/keys/key_repository.dart';
import 'package:pureshell/core/keys/key_service.dart';
import 'package:pureshell/core/keys/keystore_api.dart';
import 'package:pureshell/core/ssh/ssh_connection.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/hosts/connect_flow.dart';
import 'package:pureshell/ui/terminal/direct_input.dart';
import 'package:pureshell/ui/terminal/terminal_screen.dart';
import 'package:xterm/xterm.dart';

const _host = Host(
  id: '1',
  label: 'Test',
  hostname: 'example.com',
  username: 'u',
);

class _FakeSession implements SSHSession {
  final stdinData = StreamController<Uint8List>();
  final out = StreamController<Uint8List>();
  final doneC = Completer<void>();
  final sent = <int>[];

  _FakeSession() {
    stdinData.stream.listen(sent.addAll);
  }

  @override
  StreamSink<Uint8List> get stdin => stdinData.sink;
  @override
  Stream<Uint8List> get stdout => out.stream;
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
  var closed = false;

  @override
  SSHSession? get session => fake;

  @override
  Future<SSHSession> openShell(int columns, int rows) async =>
      fake = _FakeSession();

  @override
  void resize(int columns, int rows) {}

  @override
  void close() => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemorySecureStore store;
  late _Connection first;

  Future<void> pump(
    WidgetTester t, {
    Future<SshConnection?> Function(BuildContext)? onReconnect,
  }) async {
    PromptTracker.active.value = 0;
    store = MemorySecureStore();
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
    first = _Connection(store);
    await t.pumpWidget(
      MaterialApp(
        home: TerminalScreen(
          host: _host,
          connection: first,
          settings: TerminalSettings(store),
          onReconnect: onReconnect,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Terminal terminalOf(WidgetTester t) =>
      t.widget<TerminalView>(find.byType(TerminalView)).terminal;

  testWidgets('no Reconnect button without a reconnect flow', (t) async {
    await pump(t);
    first.fake!.doneC.complete();
    await t.pumpAndSettle();
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Reconnect'), findsNothing);
  });

  testWidgets('Reconnect keeps the scrollback, separates, new session', (
    t,
  ) async {
    final second = _Connection(store = MemorySecureStore());
    var calls = 0;
    await pump(
      t,
      onReconnect: (_) async {
        calls++;
        return second;
      },
    );
    first.fake!.out.add(utf8.encode('old output\r\n'));
    await t.pump();
    first.fake!.doneC.complete();
    await t.pumpAndSettle();
    expect(find.text('Reconnect'), findsOneWidget);

    await t.tap(find.text('Reconnect'));
    await t.pumpAndSettle();

    expect(calls, 1);
    expect(first.closed, isTrue);
    expect(find.text('Reconnect'), findsNothing); // banner gone
    final text = terminalOf(t).buffer.getText();
    expect(text, contains('old output'));
    expect(text, contains('--- reconnected ---'));
    expect(
      text.indexOf('old output'),
      lessThan(text.indexOf('--- reconnected ---')),
    );

    // The new session gets the input, the old one does not.
    second.fake!.out.add(utf8.encode('new output'));
    terminalOf(t).textInput('ls');
    await t.pump();
    expect(utf8.decode(second.fake!.sent), 'ls');
    expect(first.fake!.sent, isEmpty);
    expect(terminalOf(t).buffer.getText(), contains('new output'));
  });

  testWidgets(
    'the new session is live after a reconnect (no stale ended banner)',
    (t) async {
      final second = _Connection(MemorySecureStore());
      await pump(t, onReconnect: (_) async => second);
      first.fake!.doneC.complete();
      await t.pumpAndSettle();
      await t.tap(find.text('Reconnect'));
      await t.pumpAndSettle();
      expect(find.text('Reconnect'), findsNothing);
      expect(find.text('Close'), findsNothing);
    },
  );

  testWidgets('a failed or cancelled reconnect leaves the banner', (t) async {
    await pump(t, onReconnect: (_) async => null);
    first.fake!.doneC.complete();
    await t.pumpAndSettle();
    await t.tap(find.text('Reconnect'));
    await t.pumpAndSettle();
    expect(find.text('Reconnect'), findsOneWidget);
    expect(terminalOf(t).buffer.getText(), isNot(contains('reconnected')));
  });

  testWidgets('the connect flow asks for the password again each time', (
    t,
  ) async {
    final s = MemorySecureStore();
    var attempts = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => establishConnection(
                context,
                host: _host,
                knownHosts: KnownHostsStore(s),
                keyService: KeyService(PlatformKeystore(), KeyRepository(s)),
                socketFactory: (h, p, {timeout}) {
                  attempts++;
                  return Future.error(const SocketException('refused'));
                },
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    for (var i = 1; i <= 2; i++) {
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      // An empty field every time: nothing was remembered.
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
      await t.enterText(find.byType(TextField), 'pw');
      await t.tap(find.text('Connect'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(attempts, i);
    }
  });
}
