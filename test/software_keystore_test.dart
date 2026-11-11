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

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:pureshell/core/keys/key_repository.dart';
import 'package:pureshell/core/keys/key_service.dart';
import 'package:pureshell/core/keys/keystore_api.dart';
import 'package:pureshell/core/keys/software_keystore.dart';
import 'package:pureshell/core/storage/secure_store.dart';

void main() {
  late MemorySecureStore store;
  late SoftwareKeystore keystore;

  setUp(() {
    store = MemorySecureStore();
    keystore = SoftwareKeystore(store, random: Random(1));
  });

  test('wrap / unwrap round trip, and a tampered blob is rejected', () async {
    await keystore.generateWrapKey('a');
    final seed = Uint8List.fromList(List.generate(32, (i) => i));
    final w = await keystore.wrap('a', seed);
    expect(w.data, isNot(seed));
    expect(await keystore.unwrap('a', w.iv, w.data), seed);

    final bad = Uint8List.fromList(w.data)..[0] ^= 1;
    expect(
      () => keystore.unwrap('a', w.iv, bad),
      throwsA(isA<KeystoreException>()),
    );
  });

  test('aliases are listed until deleted; the wrap key goes too', () async {
    await keystore.generateWrapKey('a');
    await keystore.generateWrapKey('b');
    expect(await keystore.listKeys(), ['a', 'b']);
    await keystore.deleteKey('a');
    expect(await keystore.listKeys(), ['b']);
    expect(store.data.keys.where((k) => k.endsWith('.a')), isEmpty);
  });

  test('no hardware keys, no prompt', () async {
    expect(() => keystore.generateKey('x'), throwsA(isA<KeystoreException>()));
    expect(() => keystore.authenticate(), throwsA(isA<KeystoreException>()));
  });

  test('KeyService makes and signs with a software key on it', () async {
    final service = KeyService(
      keystore,
      KeyRepository(store),
      softwareOnly: true,
      random: Random(2),
    );
    final key = await service.generate(name: 'win');
    expect(key.isSoftware, isTrue);
    expect(await service.presentAliases(), {key.wrapAlias});

    final message = Uint8List.fromList(utf8.encode('hello'));
    final blob = await service.sign(key, message);
    final sig = blob.sublist(4 + 11 + 4);
    expect(
      () =>
          nacl.VerifyKey(key.publicKey)
              .verify(signature: nacl.Signature(sig), message: message),
      returnsNormally,
    );
  });
}
