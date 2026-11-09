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

/// SSH wire encoding for ECDSA P-256 keys (RFC 5656) and the conversion of
/// the Keystore's DER signatures to the SSH signature format.

const ecdsaP256Type = 'ecdsa-sha2-nistp256';
const ecdsaP256Curve = 'nistp256';

/// Default key comment. Nothing personal: no device name, no username.
const defaultKeyComment = 'pure-shell';

/// What keys made before the comment was stored (and before the rename) got.
/// A stored key without a comment keeps this: existing keys never change.
const legacyKeyComment = 'pureshell';

class SshEncodingException implements Exception {
  const SshEncodingException(this.message);
  final String message;
  @override
  String toString() => 'SshEncodingException($message)';
}

// ---- writer ---------------------------------------------------------------

Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.big);

/// SSH `string`: uint32 length followed by the bytes.
Uint8List sshString(List<int> bytes) =>
    Uint8List.fromList([..._u32(bytes.length), ...bytes]);

/// SSH `mpint` for a non-negative integer: big-endian, no redundant leading
/// zeros, and a leading 0x00 when the top bit would otherwise mark it
/// negative. Zero is the empty string.
Uint8List sshMpint(BigInt value) {
  if (value.isNegative) {
    throw const SshEncodingException('negative mpint');
  }
  if (value == BigInt.zero) return sshString(const []);
  var bytes = <int>[];
  var v = value;
  while (v > BigInt.zero) {
    bytes.add((v & BigInt.from(0xff)).toInt());
    v >>= 8;
  }
  bytes = bytes.reversed.toList();
  if (bytes.first & 0x80 != 0) bytes = [0, ...bytes];
  return sshString(bytes);
}

// ---- public key -----------------------------------------------------------

void _checkPoint(Uint8List q) {
  if (q.length != 65 || q[0] != 0x04) {
    throw const SshEncodingException(
      'expected an uncompressed P-256 point (65 bytes starting with 0x04)',
    );
  }
}

/// The public key blob: string "ecdsa-sha2-nistp256", string "nistp256",
/// string Q (0x04 || X || Y).
Uint8List ecdsaP256PublicKeyBlob(Uint8List q) {
  _checkPoint(q);
  return Uint8List.fromList([
    ...sshString(utf8.encode(ecdsaP256Type)),
    ...sshString(utf8.encode(ecdsaP256Curve)),
    ...sshString(q),
  ]);
}

/// A line for ~/.ssh/authorized_keys.
String authorizedKeysLine(Uint8List q, {String comment = defaultKeyComment}) {
  final c = comment.trim();
  final blob = base64.encode(ecdsaP256PublicKeyBlob(q));
  return c.isEmpty ? '$ecdsaP256Type $blob' : '$ecdsaP256Type $blob $c';
}

/// OpenSSH-style fingerprint (what `ssh-keygen -lf` prints).
String publicKeyFingerprint(Uint8List q) =>
    sha256Fingerprint(ecdsaP256PublicKeyBlob(q));

// ---- signature ------------------------------------------------------------

/// The two integers of an ECDSA signature.
class EcdsaRS {
  const EcdsaRS(this.r, this.s);
  final BigInt r;
  final BigInt s;
}

/// Parses a DER `ECDSA-Sig-Value ::= SEQUENCE { r INTEGER, s INTEGER }`, as
/// returned by the Android Keystore. Strict about structure, tolerant about
/// leading zeros.
EcdsaRS parseDerEcdsaSignature(Uint8List der) {
  var i = 0;
  int readByte() {
    if (i >= der.length) throw const SshEncodingException('DER truncated');
    return der[i++];
  }

  int readLength() {
    final first = readByte();
    if (first < 0x80) return first;
    final n = first & 0x7f;
    if (n == 0 || n > 2) throw const SshEncodingException('bad DER length');
    var len = 0;
    for (var k = 0; k < n; k++) {
      len = (len << 8) | readByte();
    }
    return len;
  }

  BigInt readInteger() {
    if (readByte() != 0x02) {
      throw const SshEncodingException('expected INTEGER');
    }
    final len = readLength();
    if (len == 0 || i + len > der.length) {
      throw const SshEncodingException('bad INTEGER length');
    }
    final bytes = der.sublist(i, i + len);
    i += len;
    if (bytes[0] & 0x80 != 0) {
      throw const SshEncodingException('negative INTEGER');
    }
    var v = BigInt.zero;
    for (final b in bytes) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  if (readByte() != 0x30) throw const SshEncodingException('expected SEQUENCE');
  final seqLen = readLength();
  if (i + seqLen != der.length) {
    throw const SshEncodingException('SEQUENCE length mismatch');
  }
  final r = readInteger();
  final s = readInteger();
  if (i != der.length) throw const SshEncodingException('trailing bytes');
  return EcdsaRS(r, s);
}

/// The SSH signature blob: string "ecdsa-sha2-nistp256", string (mpint r,
/// mpint s).
Uint8List ecdsaP256SignatureBlob(EcdsaRS rs) => Uint8List.fromList([
  ...sshString(utf8.encode(ecdsaP256Type)),
  ...sshString([...sshMpint(rs.r), ...sshMpint(rs.s)]),
]);

/// DER (Keystore) -> SSH signature blob.
Uint8List sshSignatureFromDer(Uint8List der) =>
    ecdsaP256SignatureBlob(parseDerEcdsaSignature(der));
