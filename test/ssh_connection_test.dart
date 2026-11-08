// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/ssh/ssh_connection.dart';

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
}
