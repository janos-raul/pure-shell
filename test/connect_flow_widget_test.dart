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

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/ssh/connect_result.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/hosts/connect_flow.dart';

const _host = Host(
  id: '1',
  label: 'Test',
  hostname: 'example.com',
  username: 'user',
);

Future<void> _start(
  WidgetTester tester,
  Future<SSHSocket> Function() factory,
) async {
  final store = MemorySecureStore();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => connectToHost(
              context,
              host: _host,
              knownHosts: KnownHostsStore(store),
              settings: TerminalSettings(store),
              socketFactory: (h, p, {timeout}) => factory(),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'pw');
  await tester.tap(find.text('Connect'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a failing connect closes the dialog and explains', (t) async {
    await _start(t, () => Future.error(const SocketException('refused')));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text(connectFailureMessage(ConnectFailure.unreachable)),
      findsOneWidget,
    );
  });

  testWidgets('the spinner can always be cancelled', (t) async {
    await _start(t, () => Completer<SSHSocket>().future);
    expect(find.text('Connecting...'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('hardware back on the spinner cancels too', (t) async {
    await _start(t, () => Completer<SSHSocket>().future);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
