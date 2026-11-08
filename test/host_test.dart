// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/hosts/host.dart';
import 'package:pureshell/core/hosts/host_repository.dart';
import 'package:pureshell/core/storage/secure_store.dart';

void main() {
  const host = Host(
    id: 'abc',
    label: 'Lab server',
    hostname: 'example.com',
    port: 2222,
    username: 'alice',
  );

  test('JSON round trip', () {
    final json = jsonDecode(jsonEncode(host.toJson())) as Map<String, dynamic>;
    expect(Host.fromJson(json), host);
  });

  test('port defaults to 22', () {
    expect(
      Host.fromJson({
        'id': '1',
        'label': 'l',
        'hostname': 'example.com',
        'username': 'u',
      }).port,
      22,
    );
  });

  test('serialized form has no password field', () {
    expect(
      host.toJson().keys,
      unorderedEquals(['id', 'label', 'hostname', 'port', 'username']),
    );
  });

  test('repository add, edit, delete', () async {
    final repo = HostRepository(MemorySecureStore());
    expect(await repo.list(), isEmpty);
    await repo.upsert(host);
    await repo.upsert(host.copyWith(label: 'Renamed'));
    final hosts = await repo.list();
    expect(hosts, hasLength(1));
    expect(hosts.single.label, 'Renamed');
    await repo.delete(host);
    expect(await repo.list(), isEmpty);
  });
}
