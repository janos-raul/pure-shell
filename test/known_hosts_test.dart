// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/host_repository.dart';
import 'package:pureshell/core/hosts/known_hosts.dart';
import 'package:pureshell/core/storage/secure_store.dart';

void main() {
  const keyA = HostKey(type: 'ssh-ed25519', fingerprint: 'SHA256:aaaa');
  const keyB = HostKey(type: 'ssh-ed25519', fingerprint: 'SHA256:bbbb');
  const keyAasRsa = HostKey(type: 'ssh-rsa', fingerprint: 'SHA256:aaaa');

  late MemorySecureStore backing;
  late KnownHostsStore store;

  setUp(() {
    backing = MemorySecureStore();
    store = KnownHostsStore(backing);
  });

  test('first use: unknown host', () async {
    final r = await store.check('example.com', 22, keyA);
    expect(r.status, KnownHostStatus.unknown);
    expect(r.stored, isNull);
  });

  test('match after trust, persisted across instances', () async {
    await store.trust('example.com', 22, keyA);
    final r = await KnownHostsStore(backing).check('example.com', 22, keyA);
    expect(r.status, KnownHostStatus.match);
  });

  test('different fingerprint is a mismatch and reports the old key', () async {
    await store.trust('example.com', 22, keyA);
    final r = await store.check('example.com', 22, keyB);
    expect(r.status, KnownHostStatus.mismatch);
    expect(r.stored, keyA);
  });

  test('different key type is a mismatch', () async {
    await store.trust('example.com', 22, keyA);
    final r = await store.check('example.com', 22, keyAasRsa);
    expect(r.status, KnownHostStatus.mismatch);
  });

  test('hostname is trimmed and lowercased', () async {
    await store.trust('  Example.COM ', 22, keyA);
    expect((await store.check('example.com', 22, keyA)).status,
        KnownHostStatus.match);
  });

  test('port and IP vs name are separate entries', () async {
    await store.trust('example.com', 22, keyA);
    expect((await store.check('example.com', 2222, keyA)).status,
        KnownHostStatus.unknown);
    expect((await store.check('192.0.2.10', 22, keyA)).status,
        KnownHostStatus.unknown);
  });

  test('trust refuses to overwrite a different key', () async {
    await store.trust('example.com', 22, keyA);
    expect(() => store.trust('example.com', 22, keyB), throwsStateError);
    expect((await store.get('example.com', 22)), keyA);
  });

  test('remove allows trusting a new key', () async {
    await store.trust('example.com', 22, keyA);
    await store.remove('example.com', 22);
    expect((await store.check('example.com', 22, keyB)).status,
        KnownHostStatus.unknown);
    await store.trust('example.com', 22, keyB);
    expect((await store.get('example.com', 22)), keyB);
  });

  test('deleting a host also removes its trusted key', () async {
    final repo = HostRepository(backing, knownHosts: store);
    const host = Host(
        id: '1', label: 'Test', hostname: 'example.com', username: 'user');
    await repo.upsert(host);
    await store.trust('example.com', 22, keyA);
    await repo.delete(host);
    expect(await repo.list(), isEmpty);
    expect(await store.get('example.com', 22), isNull);
  });
}
