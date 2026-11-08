// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where a key actually lives, as reported by the Android Keystore.
enum SecurityLevel {
  strongBox,
  tee,
  software;

  static SecurityLevel parse(String? name) => switch (name) {
    'STRONGBOX' => SecurityLevel.strongBox,
    'TEE' => SecurityLevel.tee,
    _ => SecurityLevel.software,
  };

  String get label => switch (this) {
    SecurityLevel.strongBox => 'StrongBox',
    SecurityLevel.tee => 'TEE',
    SecurityLevel.software => 'Software',
  };
}

enum KeystoreErrorKind {
  /// The user dismissed the prompt.
  cancelled,
  lockout,
  unavailable,
  noScreenLock,
  keyInvalid,
  busy,
  exists,
  failed,
}

class KeystoreException implements Exception {
  const KeystoreException(this.kind);

  final KeystoreErrorKind kind;

  static KeystoreException fromCode(String code) =>
      KeystoreException(switch (code) {
        'cancelled' => KeystoreErrorKind.cancelled,
        'lockout' => KeystoreErrorKind.lockout,
        'unavailable' => KeystoreErrorKind.unavailable,
        'no_screen_lock' => KeystoreErrorKind.noScreenLock,
        'key_invalid' => KeystoreErrorKind.keyInvalid,
        'busy' => KeystoreErrorKind.busy,
        'exists' => KeystoreErrorKind.exists,
        _ => KeystoreErrorKind.failed,
      });

  /// Fixed user-facing text; never includes platform error details.
  String get message => switch (kind) {
    KeystoreErrorKind.cancelled => 'Cancelled.',
    KeystoreErrorKind.lockout => 'Too many failed attempts. Try again later.',
    KeystoreErrorKind.unavailable =>
      'Fingerprint or screen lock is not available.',
    KeystoreErrorKind.noScreenLock => 'Set a screen lock to create keys.',
    KeystoreErrorKind.keyInvalid =>
      'This key is no longer usable. Delete it and create a new one.',
    KeystoreErrorKind.busy => 'Another prompt is already showing.',
    KeystoreErrorKind.exists => 'A key with this name already exists.',
    KeystoreErrorKind.failed => 'The key operation failed.',
  };

  @override
  String toString() => 'KeystoreException(${kind.name})';
}

class KeystoreCapabilities {
  const KeystoreCapabilities({
    required this.secureLockScreen,
    required this.canAuthenticate,
  });

  /// The phone has a PIN, pattern, password or biometric lock.
  final bool secureLockScreen;

  /// BIOMETRIC_STRONG or DEVICE_CREDENTIAL can be used right now.
  final bool canAuthenticate;
}

class GeneratedKey {
  const GeneratedKey({required this.level, required this.publicPoint});

  final SecurityLevel level;

  /// Uncompressed P-256 point: 0x04 || X || Y (65 bytes).
  final Uint8List publicPoint;
}

/// The Keystore as the rest of the app sees it. There is deliberately no
/// method that returns private key material.
abstract class KeystoreApi {
  Future<KeystoreCapabilities> capabilities();

  /// EC P-256 signing key, user authentication required for every use.
  Future<GeneratedKey> generateKey(String alias);

  Future<SecurityLevel> securityLevel(String alias);

  Future<Uint8List> publicKey(String alias);

  /// Signs [data] (SHA-256 with ECDSA) after the user authenticates. Returns
  /// the DER-encoded signature. Throws [KeystoreException] (kind cancelled if
  /// the user dismissed the prompt).
  Future<Uint8List> sign(
    String alias,
    Uint8List data, {
    String title = 'Use your key',
    String? subtitle,
  });

  Future<void> deleteKey(String alias);

  Future<List<String>> listKeys();

  /// AES-GCM key for the software-key fallback.
  Future<SecurityLevel> generateWrapKey(String alias);

  Future<({Uint8List iv, Uint8List data})> wrap(String alias, Uint8List data);

  Future<Uint8List> unwrap(String alias, Uint8List iv, Uint8List data);

  /// Biometric or device credential, no key involved (app lock).
  Future<void> authenticate({
    String title = 'Unlock PureShell',
    String? subtitle,
  });

  /// Dismisses a prompt that is showing.
  Future<void> cancelPrompt();
}

/// Counts the system prompts (fingerprint / screen lock) currently showing.
/// The app lock ignores the app losing focus while one is up, otherwise every
/// key use would lock the app again.
class PromptTracker {
  PromptTracker._();

  static final active = ValueNotifier<int>(0);
}

class PlatformKeystore implements KeystoreApi {
  PlatformKeystore([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('eu.pureshell.app/keystore');

  final MethodChannel _channel;

  /// Methods that put a system prompt on screen.
  static const _prompting = {'sign', 'wrap', 'unwrap', 'authenticate'};

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    final tracked = _prompting.contains(method);
    if (tracked) PromptTracker.active.value++;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw KeystoreException.fromCode(e.code);
    } finally {
      if (tracked) PromptTracker.active.value--;
    }
  }

  @override
  Future<KeystoreCapabilities> capabilities() async {
    final m = await _call<Map<Object?, Object?>>('capabilities');
    return KeystoreCapabilities(
      secureLockScreen: m?['secureLockScreen'] == true,
      canAuthenticate: m?['canAuthenticate'] == true,
    );
  }

  @override
  Future<GeneratedKey> generateKey(String alias) async {
    final m = await _call<Map<Object?, Object?>>('generateKey', {
      'alias': alias,
    });
    return GeneratedKey(
      level: SecurityLevel.parse(m?['securityLevel'] as String?),
      publicPoint: m?['publicKey'] as Uint8List,
    );
  }

  @override
  Future<SecurityLevel> securityLevel(String alias) async =>
      SecurityLevel.parse(
        await _call<String>('securityLevel', {'alias': alias}),
      );

  @override
  Future<Uint8List> publicKey(String alias) async =>
      (await _call<Uint8List>('publicKey', {'alias': alias}))!;

  @override
  Future<Uint8List> sign(
    String alias,
    Uint8List data, {
    String title = 'Use your key',
    String? subtitle,
  }) async => (await _call<Uint8List>('sign', {
    'alias': alias,
    'data': data,
    'title': title,
    'subtitle': subtitle,
  }))!;

  @override
  Future<void> deleteKey(String alias) =>
      _call<void>('deleteKey', {'alias': alias});

  @override
  Future<List<String>> listKeys() async =>
      ((await _call<List<Object?>>('listKeys')) ?? const []).cast<String>();

  @override
  Future<SecurityLevel> generateWrapKey(String alias) async {
    final m = await _call<Map<Object?, Object?>>('generateWrapKey', {
      'alias': alias,
    });
    return SecurityLevel.parse(m?['securityLevel'] as String?);
  }

  @override
  Future<({Uint8List iv, Uint8List data})> wrap(
    String alias,
    Uint8List data,
  ) async {
    final m = await _call<Map<Object?, Object?>>('wrap', {
      'alias': alias,
      'data': data,
    });
    return (iv: m!['iv'] as Uint8List, data: m['data'] as Uint8List);
  }

  @override
  Future<Uint8List> unwrap(String alias, Uint8List iv, Uint8List data) async =>
      (await _call<Uint8List>('unwrap', {
        'alias': alias,
        'iv': iv,
        'data': data,
      }))!;

  @override
  Future<void> authenticate({
    String title = 'Unlock PureShell',
    String? subtitle,
  }) => _call<void>('authenticate', {'title': title, 'subtitle': subtitle});

  @override
  Future<void> cancelPrompt() => _call<void>('cancelPrompt');
}
