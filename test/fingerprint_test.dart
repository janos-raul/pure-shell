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
import 'package:pureshell/core/hosts/fingerprint.dart';

void main() {
  // Throwaway ed25519 test key generated for this fixture; the expected value
  // comes from `ssh-keygen -lf` on the matching .pub file.
  const pubBlob =
      'AAAAC3NzaC1lZDI1NTE5AAAAIAV3rQEQEYHbzes4NHN4O7aYYFbv52EyCV2I+IXm+jJ4';
  const expected = 'SHA256:/fdz2YHWFRF5s0eY7JfpH3h7D4zlRvbK6/a16eQuzVA';

  test('formats SHA-256 fingerprint like ssh-keygen -lf', () {
    expect(sha256Fingerprint(base64.decode(pubBlob)), expected);
  });

  test('matches ssh-keygen -lf for an RSA key', () {
    const rsaBlob =
        'AAAAB3NzaC1yc2EAAAADAQABAAABAQCVSmYshyaZGJhUclifDFtYVAUNEBzt/Gu29b6bwCYATE4XJbqdQyg0l3pTMqJL5hTSmWaJTgWYKneAGjCFApTjDhFlU2TQSLTmEp5dTS+MMXhqWnobZ7giGIO4++hLVWGiELmKdQHt7H1bXz9ufATPxFw9F5Qsm5mv9MYWu8u851nrrt1Xe4ODYh3Ss+JuECMUMOoAl/dsIxnWNLjOms3xP5kpLMgoiGqjAZdBZBsmwQ29lAzIDA6nxcPWwAIH3j86q7gsai9GIDq8Nz3LLwgZYVzueDCot2ScI0h75HXaaPi+KcM6jpc7Qz9L65rpIo12gCvLmVZHKBiFKKEu0fPB';
    expect(sha256Fingerprint(base64.decode(rsaBlob)), 'SHA256:JsLFbeIAjnGJyi7RgKyJcX3ImLtGaEHKnv4eudznKAk');
  });

  test('has no base64 padding', () {
    expect(sha256Fingerprint(Uint8List.fromList([1, 2, 3])).contains('='),
        isFalse);
  });

  test('decodes the dartssh2 callback bytes', () {
    final bytes = Uint8List.fromList(utf8.encode('SHA256:abc'));
    expect(fingerprintFromCallback(bytes), 'SHA256:abc');
  });
}
