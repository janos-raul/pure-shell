// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/ssh/ssh_connection.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/terminal/terminal_screen.dart';

/// A connection that records PTY resizes instead of talking to a server.
class RecordingConnection extends SshConnection {
  RecordingConnection(MemorySecureStore store)
    : super(
        host: const Host(
          id: '1',
          label: 'Test',
          hostname: 'example.com',
          username: 'u',
        ),
        knownHosts: KnownHostsStore(store),
        onTrustPrompt: (key, closed) async => true,
      );

  final resizes = <(int, int)>[];

  @override
  void resize(int columns, int rows) => resizes.add((columns, rows));

  @override
  Future<SSHSession> openShell(int columns, int rows) async =>
      throw UnimplementedError('no server in this test');

  @override
  void close() {}
}

void main() {
  testWidgets('a pinch with many steps sends exactly one PTY resize', (
    t,
  ) async {
    final store = MemorySecureStore();
    final conn = RecordingConnection(store);
    final settings = TerminalSettings(store);
    await t.pumpWidget(
      MaterialApp(
        home: TerminalScreen(
          host: const Host(
            id: '1',
            label: 'Test',
            hostname: 'example.com',
            username: 'u',
          ),
          connection: conn,
          settings: settings,
        ),
      ),
    );
    // First layout and its debounced size.
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final before = conn.resizes.length;
    final initial = await settings.loadFontSize();

    const y = 250.0;
    final a = await t.startGesture(const Offset(180, y), pointer: 1);
    final b = await t.startGesture(const Offset(220, y), pointer: 2);
    for (var i = 1; i <= 40; i++) {
      await a.moveTo(Offset(180.0 - i * 3, y));
      await b.moveTo(Offset(220.0 + i * 3, y));
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(
      conn.resizes.length,
      before,
      reason: 'the font changed 40 times on screen, yet nothing was sent',
    );

    await a.up();
    await b.up();
    await t.pump();
    expect(
      conn.resizes.length,
      before + 1,
      reason: 'exactly one resize when the pinch ends',
    );
    expect(
      await settings.loadFontSize(),
      greaterThan(initial),
      reason: 'the pinch really zoomed',
    );

    await t.pump(const Duration(seconds: 1));
    expect(conn.resizes.length, before + 1);
    // The size sent is the final one, not an intermediate step.
    final (cols, rows) = conn.resizes.last;
    expect(cols, greaterThan(0));
    expect(rows, greaterThan(0));
    if (before > 0) expect((cols, rows), isNot(conn.resizes.first));
  });

  testWidgets('a pinch in then out sends one resize, not a flood', (t) async {
    final store = MemorySecureStore();
    final conn = RecordingConnection(store);
    await t.pumpWidget(
      MaterialApp(
        home: TerminalScreen(
          host: const Host(
            id: '1',
            label: 'Test',
            hostname: 'example.com',
            username: 'u',
          ),
          connection: conn,
          settings: TerminalSettings(store),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final before = conn.resizes.length;

    final a = await t.startGesture(const Offset(150, 250), pointer: 1);
    final b = await t.startGesture(const Offset(250, 250), pointer: 2);
    for (var i = 1; i <= 15; i++) {
      await a.moveTo(Offset(150.0 - i * 5, 250));
      await b.moveTo(Offset(250.0 + i * 5, 250));
      await t.pump(const Duration(milliseconds: 16));
    }
    for (var i = 15; i >= 0; i--) {
      await a.moveTo(Offset(150.0 - i * 5, 250));
      await b.moveTo(Offset(250.0 + i * 5, 250));
      await t.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await t.pump(const Duration(seconds: 1));
    // Back at the starting grid: nothing new to tell the server.
    expect(conn.resizes.length, before);
  });
}
