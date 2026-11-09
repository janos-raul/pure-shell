// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/keys/ssh_ed25519_encoding.dart';
import 'package:pureshell/core/keys/ssh_ec_encoding.dart';

// A throwaway Ed25519 key made with `ssh-keygen -t ed25519`; public half only,
// fingerprint from `ssh-keygen -lf`.
const _blobB64 =
    'AAAAC3NzaC1lZDI1NTE5AAAAIKF4HinQmat7wt6Re3UdaNI/ob4jBJS76Zt4zvo2BnJW';
const _fingerprint = 'SHA256:4s7zXdkflvhMRQqQIgemmqKATVNrkTvtNuwvIbB2qWY';

void main() {
  final blob = base64.decode(_blobB64);
  final pk = Uint8List.fromList(blob.sublist(blob.length - 32));

  test('blob and line match ssh-keygen output', () {
    expect(ed25519PublicKeyBlob(pk), blob);
    expect(ed25519AuthorizedKeysLine(pk), 'ssh-ed25519 $_blobB64 pure-shell');
  });

  test('fingerprint equals ssh-keygen -lf', () {
    expect(ed25519Fingerprint(pk), _fingerprint);
  });

  test('signature blob layout and size checks', () {
    final sig = Uint8List(64);
    final b = ed25519SignatureBlob(sig);
    expect(b.length, 4 + 11 + 4 + 64);
    expect(
      () => ed25519SignatureBlob(Uint8List(63)),
      throwsA(isA<SshEncodingException>()),
    );
    expect(
      () => ed25519PublicKeyBlob(Uint8List(31)),
      throwsA(isA<SshEncodingException>()),
    );
  });
}
