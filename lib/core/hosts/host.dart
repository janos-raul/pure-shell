// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

enum AuthMethod { password, key }

/// A saved SSH host. Never contains a password.
class Host {
  const Host({
    required this.id,
    required this.label,
    required this.hostname,
    required this.username,
    this.port = 22,
    this.authMethod = AuthMethod.password,
    this.keyId,
    this.allowPasswordFallback = false,
  });

  final String id;
  final String label;
  final String hostname;
  final int port;
  final String username;

  /// How to log in. For [AuthMethod.key], [keyId] names one of the user's keys.
  final AuthMethod authMethod;
  final String? keyId;

  /// Key login only: if the server rejects the key, offer (never silently
  /// use) a password login.
  final bool allowPasswordFallback;

  Host copyWith({
    String? label,
    String? hostname,
    int? port,
    String? username,
    AuthMethod? authMethod,
    String? keyId,
    bool clearKey = false,
    bool? allowPasswordFallback,
  }) => Host(
    id: id,
    label: label ?? this.label,
    hostname: hostname ?? this.hostname,
    port: port ?? this.port,
    username: username ?? this.username,
    authMethod: authMethod ?? this.authMethod,
    keyId: clearKey ? null : (keyId ?? this.keyId),
    allowPasswordFallback: allowPasswordFallback ?? this.allowPasswordFallback,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'hostname': hostname,
    'port': port,
    'username': username,
    'authMethod': authMethod.name,
    if (keyId != null) 'keyId': keyId,
    'allowPasswordFallback': allowPasswordFallback,
  };

  factory Host.fromJson(Map<String, dynamic> json) => Host(
    id: json['id'] as String,
    label: json['label'] as String,
    hostname: json['hostname'] as String,
    port: (json['port'] as num?)?.toInt() ?? 22,
    username: json['username'] as String,
    authMethod:
        AuthMethod.values.asNameMap()[json['authMethod']] ??
        AuthMethod.password,
    keyId: json['keyId'] as String?,
    allowPasswordFallback: json['allowPasswordFallback'] == true,
  );

  @override
  bool operator ==(Object other) =>
      other is Host &&
      other.id == id &&
      other.label == label &&
      other.hostname == hostname &&
      other.port == port &&
      other.username == username &&
      other.authMethod == authMethod &&
      other.keyId == keyId &&
      other.allowPasswordFallback == allowPasswordFallback;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    hostname,
    port,
    username,
    authMethod,
    keyId,
    allowPasswordFallback,
  );
}
