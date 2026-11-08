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

import '../hosts/fingerprint.dart';
import 'ssh_ec_encoding.dart';

/// SSH wire encoding for Ed25519 keys (RFC 8709), used by the software-key
/// fallback only.

const ed25519Type = 'ssh-ed25519';

Uint8List ed25519PublicKeyBlob(Uint8List publicKey) {
  if (publicKey.length != 32) {
    throw const SshEncodingException('an Ed25519 public key is 32 bytes');
  }
  return Uint8List.fromList([
    ...sshString(utf8.encode(ed25519Type)),
    ...sshString(publicKey),
  ]);
}

String ed25519AuthorizedKeysLine(
  Uint8List publicKey, {
  String comment = defaultKeyComment,
}) {
  final c = comment.trim();
  final blob = base64.encode(ed25519PublicKeyBlob(publicKey));
  return c.isEmpty ? '$ed25519Type $blob' : '$ed25519Type $blob $c';
}

String ed25519Fingerprint(Uint8List publicKey) =>
    sha256Fingerprint(ed25519PublicKeyBlob(publicKey));

/// string "ssh-ed25519", string signature (64 bytes).
Uint8List ed25519SignatureBlob(Uint8List signature) {
  if (signature.length != 64) {
    throw const SshEncodingException('an Ed25519 signature is 64 bytes');
  }
  return Uint8List.fromList([
    ...sshString(utf8.encode(ed25519Type)),
    ...sshString(signature),
  ]);
}
