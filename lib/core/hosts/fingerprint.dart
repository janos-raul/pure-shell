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

import 'package:crypto/crypto.dart';

/// OpenSSH-style fingerprint of a raw host key blob (the base64-decoded
/// middle field of a `known_hosts` / `.pub` line):
/// `SHA256:` + base64(sha256(blob)) without padding.
String sha256Fingerprint(Uint8List keyBlob) =>
    'SHA256:${base64.encode(sha256.convert(keyBlob).bytes).replaceAll('=', '')}';

/// Decodes the fingerprint bytes handed over by dartssh2's host key callback
/// (UTF-8 `SHA256:<base64>`).
String fingerprintFromCallback(Uint8List bytes) =>
    utf8.decode(bytes, allowMalformed: true);
