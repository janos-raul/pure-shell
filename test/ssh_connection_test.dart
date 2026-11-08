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
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/ssh/connect_result.dart';
import 'package:pureshell/core/ssh/ssh_connection.dart';
import 'package:pureshell/core/storage/secure_store.dart';

/// A socket whose far end the test controls.
class FakeSocket implements SSHSocket {
  final _incoming = StreamController<Uint8List>();
  final _outgoing = StreamController<List<int>>();
  final _done = Completer<void>();
  var destroyed = false;

  void closeFromServer() => _incoming.close();
  void failFromServer() => _incoming.addError(StateError('reset'));

  @override
  Stream<Uint8List> get stream => _incoming.stream;
  @override
  StreamSink<List<int>> get sink => _outgoing.sink;
  @override
  Future<void> get done => _done.future;
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  void destroy() {
    destroyed = true;
    if (!_done.isCompleted) _done.complete();
  }
}

Uint8List fp(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('RSA signature algorithms normalize to one key type', () {
    expect(normalizeKeyType('rsa-sha2-256'), 'ssh-rsa');
    expect(normalizeKeyType('rsa-sha2-512'), 'ssh-rsa');
    expect(normalizeKeyType('ssh-ed25519'), 'ssh-ed25519');
  });

  test('host key order is fixed and never offers SHA-1 RSA', () {
    final order = hostKeyPreference();
    expect(order.first, SSHHostkeyType.ed25519);
    expect(order, isNot(contains(SSHHostkeyType.rsaSha1)));
    expect(hostKeyPreference(), order);
  });

  test('stored key type is preferred first, others stay available', () {
    final order = hostKeyPreference(storedType: 'ssh-rsa');
    expect(order.take(2), [SSHHostkeyType.rsaSha512, SSHHostkeyType.rsaSha256]);
    expect(order, contains(SSHHostkeyType.ed25519));
    expect(
      hostKeyPreference(storedType: 'ecdsa-sha2-nistp256').first,
      SSHHostkeyType.ecdsa256,
    );
  });

  group('connect lifetime', () {
    const host = Host(
      id: '1',
      label: 'Test',
      hostname: 'example.com',
      username: 'user',
    );
    late KnownHostsStore known;
    late FakeSocket socket;

    SshConnection make({
      required TrustPrompt prompt,
      Future<SSHSocket> Function()? factory,
      Duration watchdog = const Duration(seconds: 30),
    }) => SshConnection(
      host: host,
      knownHosts: known,
      onTrustPrompt: prompt,
      socketFactory: (h, p, {timeout}) =>
          factory != null ? factory() : Future.value(socket),
      watchdog: watchdog,
      watchdogTick: const Duration(milliseconds: 20),
    );

    setUp(() {
      known = KnownHostsStore(MemorySecureStore());
      socket = FakeSocket();
    });

    test(
      'server closes while the Trust prompt is open: serverClosed fast',
      () async {
        final decision = Completer<bool>();
        Future<void>? closedSignal;
        final conn = make(
          prompt: (key, closed) {
            closedSignal = closed;
            return decision.future;
          },
        );
        final outcomeF = conn.connect('pw');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final verify = conn.verifyHostKey('ssh-ed25519', fp('SHA256:abc'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(closedSignal, isNotNull);

        socket.closeFromServer();

        final outcome = await outcomeF.timeout(const Duration(seconds: 2));
        expect(outcome.result, ConnectResult.serverClosed);
        expect(outcome.pendingKey?.fingerprint, 'SHA256:abc');
        await closedSignal!.timeout(const Duration(seconds: 1));
        expect(socket.destroyed, isTrue);

        // The user taps Trust after the fact: the key is kept, the late
        // callback answers false, nothing throws.
        decision.complete(true);
        expect(await verify, isFalse);
        expect((await known.get('example.com', 22))?.fingerprint, 'SHA256:abc');
      },
    );

    test('Cancel in the prompt stores nothing and answers declined', () async {
      final conn = make(prompt: (key, closed) async => false);
      final outcomeF = conn.connect('pw');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        await conn.verifyHostKey('ssh-ed25519', fp('SHA256:abc')),
        isFalse,
      );
      final outcome = await outcomeF.timeout(const Duration(seconds: 2));
      expect(outcome.result, ConnectResult.firstUseDeclined);
      expect(await known.get('example.com', 22), isNull);
    });

    test(
      'cancel() during the prompt completes immediately and closes',
      () async {
        final decision = Completer<bool>();
        final conn = make(prompt: (key, closed) => decision.future);
        final outcomeF = conn.connect('pw');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final verify = conn.verifyHostKey('ssh-ed25519', fp('SHA256:abc'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        conn.cancel();
        final outcome = await outcomeF.timeout(const Duration(seconds: 1));
        expect(outcome.result, ConnectResult.cancelled);
        expect(socket.destroyed, isTrue);
        decision.complete(false);
        expect(await verify, isFalse);
        expect(await known.get('example.com', 22), isNull);
      },
    );

    test('cancel() while the socket is still connecting', () async {
      final late = Completer<SSHSocket>();
      final conn = make(
        prompt: (key, closed) async => false,
        factory: () => late.future,
      );
      final outcomeF = conn.connect('pw');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      conn.cancel();
      expect(
        (await outcomeF.timeout(const Duration(seconds: 1))).result,
        ConnectResult.cancelled,
      );
      // The socket that arrives afterwards is thrown away.
      late.complete(socket);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(socket.destroyed, isTrue);
    });

    test('watchdog ends a connect that never makes progress', () async {
      final conn = make(
        prompt: (key, closed) async => false,
        factory: () => Completer<SSHSocket>().future,
        watchdog: const Duration(milliseconds: 200),
      );
      final outcome = await conn
          .connect('pw')
          .timeout(const Duration(seconds: 2));
      expect(outcome.result, ConnectResult.otherError);
      expect(outcome.failure, ConnectFailure.timeout);
    });

    test('watchdog does not run while the Trust prompt is open', () async {
      final decision = Completer<bool>();
      final conn = make(
        prompt: (key, closed) => decision.future,
        watchdog: const Duration(milliseconds: 150),
      );
      final outcomeF = conn.connect('pw');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      unawaited(conn.verifyHostKey('ssh-ed25519', fp('SHA256:abc')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(conn.finished, isFalse);
      conn.cancel();
      expect((await outcomeF).result, ConnectResult.cancelled);
    });

    test('socket error mid-connect is serverClosed', () async {
      final conn = make(prompt: (key, closed) async => false);
      final outcomeF = conn.connect('pw');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      socket.failFromServer();
      final outcome = await outcomeF.timeout(const Duration(seconds: 2));
      expect(outcome.result, ConnectResult.serverClosed);
      expect(outcome.pendingKey, isNull);
    });

    test('changed key is a mismatch and answers false', () async {
      await known.trust(
        'example.com',
        22,
        const HostKey(type: 'ssh-ed25519', fingerprint: 'SHA256:old'),
      );
      final conn = make(prompt: (key, closed) async => true);
      final outcomeF = conn.connect('pw');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        await conn.verifyHostKey('ssh-ed25519', fp('SHA256:new')),
        isFalse,
      );
      final outcome = await outcomeF.timeout(const Duration(seconds: 2));
      expect(outcome.result, ConnectResult.mismatch);
      expect(outcome.storedKey?.fingerprint, 'SHA256:old');
      expect(outcome.presentedKey?.fingerprint, 'SHA256:new');
    });
  });
}
