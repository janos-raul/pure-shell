// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/hosts/connect_flow.dart';

void main() {
  group('TerminalSettings', () {
    test('default font gives a sane value and is persisted', () async {
      final store = MemorySecureStore();
      final settings = TerminalSettings(store);
      expect(await settings.loadFontSize(), TerminalSettings.defaultFontSize);
      await settings.saveFontSize(13.5);
      expect(await TerminalSettings(store).loadFontSize(), 13.5);
    });

    test('values are clamped and garbage is ignored', () async {
      final store = MemorySecureStore();
      final settings = TerminalSettings(store);
      await settings.saveFontSize(500);
      expect(await settings.loadFontSize(), TerminalSettings.maxFontSize);
      store.data[TerminalSettings.fontSizeKey] = 'not a number';
      expect(await settings.loadFontSize(), TerminalSettings.defaultFontSize);
    });
  });

  group('ConnectController', () {
    const host = Host(
      id: '1',
      label: 'Test',
      hostname: 'example.com',
      username: 'user',
    );
    const key = HostKey(type: 'ssh-ed25519', fingerprint: 'SHA256:abc');

    test('server closing during the prompt updates it live', () async {
      final closed = Completer<void>();
      final c = ConnectController(
        host: host,
        knownHosts: KnownHostsStore(MemorySecureStore()),
      );
      c.askTrust(key, closed.future);
      expect(c.phase, ConnectPhase.askTrust);
      expect(c.serverClosed, isFalse);
      closed.complete();
      await Future<void>.delayed(Duration.zero);
      expect(c.serverClosed, isTrue);
      c.dispose();
    });

    test(
      'Trust after the server closed stores the key and offers reconnect',
      () async {
        final known = KnownHostsStore(MemorySecureStore());
        final closed = Completer<void>()..complete();
        final c = ConnectController(host: host, knownHosts: known);
        final decision = c.askTrust(key, closed.future);
        await Future<void>.delayed(Duration.zero);
        await c.trust();
        expect(await decision, isTrue);
        expect(c.phase, ConnectPhase.trustedAfterClose);
        expect(await known.get('example.com', 22), key);
        c.dispose();
      },
    );

    test('Trust while still connected just continues', () async {
      final known = KnownHostsStore(MemorySecureStore());
      final c = ConnectController(host: host, knownHosts: known);
      final decision = c.askTrust(key, Completer<void>().future);
      await c.trust();
      expect(await decision, isTrue);
      expect(c.phase, ConnectPhase.connecting);
      c.dispose();
    });

    test('Cancel declines and stores nothing', () async {
      final known = KnownHostsStore(MemorySecureStore());
      final c = ConnectController(host: host, knownHosts: known);
      final decision = c.askTrust(key, Completer<void>().future);
      c.decline();
      expect(await decision, isFalse);
      expect(await known.get('example.com', 22), isNull);
      c.dispose();
    });
  });
}
