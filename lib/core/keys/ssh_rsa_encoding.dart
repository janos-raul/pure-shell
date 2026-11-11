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

/// SSH wire encoding for RSA keys (RFC 4253 key format, RFC 8332
/// signatures), used by Windows Hello keys. Signatures are always
/// `rsa-sha2-256`, never `ssh-rsa` (SHA-1).

/// The key type in the public key blob and the authorized_keys line.
const rsaKeyType = 'ssh-rsa';

/// The signature / userauth algorithm.
const rsaSha256Algorithm = 'rsa-sha2-256';

const _bcryptRsaPublicMagic = 0x31415352; // "RSA1"

BigInt _unsigned(Uint8List bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

/// The SSH `ssh-rsa` public key blob from a CNG BCRYPT_RSAPUBLIC_BLOB
/// (BCRYPT_RSAKEY_BLOB header: Magic, BitLength, cbPublicExp, cbModulus,
/// cbPrime1, cbPrime2, all little-endian; then exponent and modulus,
/// big-endian).
Uint8List rsaPublicKeyBlobFromBcrypt(Uint8List blob) {
  if (blob.length < 24) {
    throw const SshEncodingException('RSA public blob too short');
  }
  final h = ByteData.sublistView(blob, 0, 24);
  final magic = h.getUint32(0, Endian.little);
  final bits = h.getUint32(4, Endian.little);
  final cbExp = h.getUint32(8, Endian.little);
  final cbMod = h.getUint32(12, Endian.little);
  if (magic != _bcryptRsaPublicMagic || blob.length != 24 + cbExp + cbMod) {
    throw const SshEncodingException('not a BCRYPT_RSAPUBLIC_BLOB');
  }
  if (bits < 2048 || cbMod * 8 != bits) {
    throw const SshEncodingException('RSA keys must be at least 2048 bits');
  }
  final e = _unsigned(Uint8List.sublistView(blob, 24, 24 + cbExp));
  final n = _unsigned(Uint8List.sublistView(blob, 24 + cbExp));
  return rsaPublicKeyBlob(e: e, n: n);
}

/// string "ssh-rsa", mpint e, mpint n.
Uint8List rsaPublicKeyBlob({required BigInt e, required BigInt n}) =>
    Uint8List.fromList([
      ...sshString(utf8.encode(rsaKeyType)),
      ...sshMpint(e),
      ...sshMpint(n),
    ]);

String rsaAuthorizedKeysLine(
  Uint8List publicKeyBlob, {
  String comment = defaultKeyComment,
}) {
  final c = comment.trim();
  final b64 = base64.encode(publicKeyBlob);
  return c.isEmpty ? '$rsaKeyType $b64' : '$rsaKeyType $b64 $c';
}

String rsaFingerprint(Uint8List publicKeyBlob) =>
    sha256Fingerprint(publicKeyBlob);

/// string "rsa-sha2-256", string signature. [signature] is the raw
/// RSASSA-PKCS1-v1_5 / SHA-256 signature, as long as the modulus.
Uint8List rsaSha256SignatureBlob(Uint8List signature) {
  if (signature.length < 256) {
    throw const SshEncodingException('RSA signature too short');
  }
  return Uint8List.fromList([
    ...sshString(utf8.encode(rsaSha256Algorithm)),
    ...sshString(signature),
  ]);
}
