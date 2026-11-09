// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// The cross-check below uses dartssh2's own ECDSA classes, which are not part
// of its public API.
// ignore: implementation_imports
import 'package:dartssh2/src/hostkey/hostkey_ecdsa.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:pureshell/core/keys/ssh_ec_encoding.dart';

// A throwaway P-256 key made with openssl, converted with
// `ssh-keygen -i -m PKCS8`. Only the public half is here.
const _line =
    'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBSnHk7bfNEFChR9rieyN5+Xwf1g+j0pkjW/hVvnnBr48EQPgll//dEa2mtUjPkp7eKLH1MaEaBi5o4ZxvPthmc=';
const _q =
    '0414a71e4edb7cd1050a147dae27b2379f97c1fd60fa3d299235bf855be79c1af8f0440f82597ffdd11ada6b548cf929ede28b1f531a11a062e68e19c6f3ed8667';
// `ssh-keygen -lf` on that public key.
const _fingerprint = 'SHA256:hxfJKzUDNXun9psaig5kWgVVJvMcFVJfA7KuJdtAfIM';
final _message = utf8.encode('pureshell test vector');

// Real DER signatures (openssl dgst -sha256 -sign) over _message, picked to
// hit each edge case.
const _derSignatures = <String, String>{
  's_high': '30450220515b7a3d03b6971c10a80edcba0623ee1c3ed486de3af70dd9a061a5b7bfa8fa022100e5e0aac169e31cb269182a8761da8676503065f42cd3286821a9f014bd9fd6a7',
  'r_high': '3046022100bebc285a9b9404cb3962b410cc3913ee2e564489224aaecb569117e947546678022100af068f253d878235765d3b4d124ce773a22aec7ddb15b2039174f99cdbb723b5',
  'plain': '304402202ee16b34c57658bb78b11884997899c419bf225f332689bae17286e242dba89a022020730af7e6960b716b4e879372ebb930651071cb833445b0eddde3a9b33c0a6b',
  'r_short': '3043021f409b0767be5bb7a0acbe6aca35e782cafeb6644d3fa4f7ad400af495a78aef02203dd8f2e2d9748a717d6133efd2b827965a21df6504d6a8b932d02c575974a3c2',
  's_short': '3045022100d5d638b5e3867494f09fab8b7184b0f163c5173037bc04d6e10bca1c9e17981e022000e12f9032473aa278e3bc83df9353a9b0f5488ce507736752e07972d5f771b0',
};

Uint8List _hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

Uint8List _derInt(BigInt v) {
  var bytes = <int>[];
  var x = v;
  while (x > BigInt.zero) {
    bytes.add((x & BigInt.from(0xff)).toInt());
    x >>= 8;
  }
  bytes = bytes.reversed.toList();
  if (bytes.isEmpty) bytes = [0];
  if (bytes.first & 0x80 != 0) bytes = [0, ...bytes];
  return Uint8List.fromList([0x02, bytes.length, ...bytes]);
}

Uint8List _derSig(BigInt r, BigInt s) {
  final body = [..._derInt(r), ..._derInt(s)];
  return Uint8List.fromList([0x30, body.length, ...body]);
}

void main() {
  final q = _hex(_q);

  group('public key', () {
    test('authorized_keys line matches ssh-keygen output plus the comment', () {
      expect(authorizedKeysLine(q), '$_line pure-shell');
      expect(authorizedKeysLine(q, comment: 'laptop key'), '$_line laptop key');
      expect(authorizedKeysLine(q, comment: '  '), _line);
    });

    test('fingerprint equals ssh-keygen -lf', () {
      expect(publicKeyFingerprint(q), _fingerprint);
    });

    test('blob layout: string type, string curve, string point', () {
      final blob = ecdsaP256PublicKeyBlob(q);
      expect(blob, base64.decode(_line.split(' ')[1]));
      final key = SSHEcdsaPublicKey.decode(blob);
      expect(key.type, 'ecdsa-sha2-nistp256');
      expect(key.curveId, 'nistp256');
      expect(key.q, q);
    });

    test('rejects points that are not uncompressed P-256', () {
      expect(
        () => ecdsaP256PublicKeyBlob(Uint8List(64)),
        throwsA(isA<SshEncodingException>()),
      );
      expect(
        () => ecdsaP256PublicKeyBlob(
          Uint8List.fromList([0x02, ...q.sublist(1, 33)]),
        ),
        throwsA(isA<SshEncodingException>()),
      );
    });

    test('default comment carries nothing personal', () {
      expect(defaultKeyComment, 'pure-shell');
    });
  });

  group('mpint', () {
    Uint8List mp(int v) => sshMpint(BigInt.from(v));
    test('high bit set gets a leading zero byte', () {
      expect(mp(0x80), [0, 0, 0, 2, 0x00, 0x80]);
      expect(mp(0xff), [0, 0, 0, 2, 0x00, 0xff]);
    });
    test('no padding when the high bit is clear', () {
      expect(mp(0x7f), [0, 0, 0, 1, 0x7f]);
    });
    test('zero is empty and values are minimal', () {
      expect(sshMpint(BigInt.zero), [0, 0, 0, 0]);
      expect(mp(1), [0, 0, 0, 1, 1]);
      expect(sshMpint(BigInt.parse('0100', radix: 16)), [0, 0, 0, 2, 1, 0]);
    });
  });

  group('DER -> SSH signature', () {
    test('parses the integers and strips leading zeros', () {
      final rs = parseDerEcdsaSignature(_hex('3009020300008102020100'));
      expect(rs.r, BigInt.from(0x81));
      expect(rs.s, BigInt.from(0x100));
    });

    test('r with the high bit set needs the 0x00 in SSH too', () {
      final der = _derSig(BigInt.parse('80' * 32, radix: 16), BigInt.from(5));
      final rs = parseDerEcdsaSignature(der);
      final blob = ecdsaP256SignatureBlob(rs);
      final sig = SSHEcdsaSignature.decode(blob);
      expect(sig.r, BigInt.parse('80' * 32, radix: 16));
      expect(sig.s, BigInt.from(5));
      // string type | string( mpint r (33 bytes) | mpint s (1 byte) )
      final inner = blob.sublist(4 + 19 + 4);
      expect(inner.sublist(0, 4), [0, 0, 0, 33]);
      expect(inner[4], 0x00);
      expect(inner[5], 0x80);
    });

    test('short r and s (fewer than 32 bytes) survive', () {
      final r = BigInt.parse('01' * 20, radix: 16);
      final s = BigInt.parse('7f', radix: 16);
      final rs = parseDerEcdsaSignature(_derSig(r, s));
      expect(rs.r, r);
      expect(rs.s, s);
      final sig = SSHEcdsaSignature.decode(ecdsaP256SignatureBlob(rs));
      expect(sig.r, r);
      expect(sig.s, s);
    });

    test('long-form lengths and redundant leading zeros are accepted', () {
      // SEQUENCE with a 0x81 length, INTEGER 00 00 05 (redundant zeros).
      final body = [0x02, 0x03, 0x00, 0x00, 0x05, 0x02, 0x01, 0x07];
      final der = Uint8List.fromList([0x30, 0x81, body.length, ...body]);
      final rs = parseDerEcdsaSignature(der);
      expect(rs.r, BigInt.from(5));
      expect(rs.s, BigInt.from(7));
    });

    test('malformed DER is rejected', () {
      void bad(List<int> b) => expect(
        () => parseDerEcdsaSignature(Uint8List.fromList(b)),
        throwsA(isA<SshEncodingException>()),
      );
      bad([]);
      bad([0x31, 0x00]); // not a SEQUENCE
      bad([0x30, 0x06, 0x02, 0x01, 0x05, 0x02, 0x01]); // truncated
      bad([0x30, 0x06, 0x02, 0x01, 0x05, 0x03, 0x01, 0x07]); // not an INTEGER
      bad([0x30, 0x06, 0x02, 0x01, 0x85, 0x02, 0x01, 0x07]); // negative
      bad([0x30, 0x07, 0x02, 0x01, 0x05, 0x02, 0x01, 0x07, 0x00]); // trailing
      bad([0x30, 0x05, 0x02, 0x00, 0x02, 0x01, 0x07]); // empty INTEGER
    });

    for (final entry in _derSignatures.entries) {
      test(
        'real openssl signature "${entry.key}" verifies after conversion',
        () {
          final der = _hex(entry.value);
          final blob = sshSignatureFromDer(der);
          final key = SSHEcdsaPublicKey.decode(ecdsaP256PublicKeyBlob(q));
          final sig = SSHEcdsaSignature.decode(blob);
          expect(sig.type, 'ecdsa-sha2-nistp256');
          expect(key.verify(Uint8List.fromList(_message), sig), isTrue);
          // And dartssh2 encodes it back to exactly our bytes.
          expect(sig.encode(), blob);
        },
      );
    }

    test('the edge cases are really present in the vectors', () {
      Uint8List ints(String k, int which) {
        final d = _hex(_derSignatures[k]!);
        final rl = d[3];
        return which == 0
            ? d.sublist(4, 4 + rl)
            : d.sublist(6 + rl, 6 + rl + d[5 + rl]);
      }

      expect(ints('r_high', 0).length, 33);
      expect(ints('r_high', 0)[0], 0);
      expect(ints('s_high', 1).length, 33);
      expect(ints('r_short', 0).length, lessThan(32));
      expect(
        ints('s_short', 1).where((b) => true).length,
        lessThanOrEqualTo(33),
      );
    });

    test('round trip against a software P-256 implementation', () {
      final rnd = FortunaRandom()
        ..seed(
          KeyParameter(Uint8List.fromList(List.generate(32, (i) => i * 7 + 1))),
        );
      final gen = ECKeyGenerator()
        ..init(
          ParametersWithRandom(
            ECKeyGeneratorParameters(ECCurve_secp256r1()),
            rnd,
          ),
        );
      final pair = gen.generateKeyPair();
      final priv = pair.privateKey;
      final pub = pair.publicKey;
      final point = pub.Q!.getEncoded(false);
      final pubBlob = SSHEcdsaPublicKey.decode(ecdsaP256PublicKeyBlob(point));

      var sawHigh = 0, sawShort = 0;
      final r2 = Random(42);
      for (var n = 0; n < 400; n++) {
        final msg = Uint8List.fromList(
          List.generate(40, (_) => r2.nextInt(256)),
        );
        final signer = ECDSASigner(SHA256Digest())
          ..init(true, ParametersWithRandom(PrivateKeyParameter(priv), rnd));
        final sig = signer.generateSignature(msg) as ECSignature;
        if (sig.r.bitLength % 8 == 0 || sig.s.bitLength % 8 == 0) sawHigh++;
        if (sig.r.bitLength <= 248 || sig.s.bitLength <= 248) sawShort++;
        final der = _derSig(sig.r, sig.s);
        final blob = sshSignatureFromDer(der);
        final back = SSHEcdsaSignature.decode(blob);
        expect(back.r, sig.r);
        expect(back.s, sig.s);
        expect(pubBlob.verify(msg, back), isTrue);
      }
      expect(sawHigh, greaterThan(0), reason: 'high-bit cases covered');
      expect(sawShort, greaterThan(0), reason: 'short cases covered');
    });
  });
}
