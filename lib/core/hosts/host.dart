// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

/// A saved SSH host. Never contains a password.
class Host {
  const Host({
    required this.id,
    required this.label,
    required this.hostname,
    required this.username,
    this.port = 22,
  });

  final String id;
  final String label;
  final String hostname;
  final int port;
  final String username;

  Host copyWith({
    String? label,
    String? hostname,
    int? port,
    String? username,
  }) =>
      Host(
        id: id,
        label: label ?? this.label,
        hostname: hostname ?? this.hostname,
        port: port ?? this.port,
        username: username ?? this.username,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'hostname': hostname,
        'port': port,
        'username': username,
      };

  factory Host.fromJson(Map<String, dynamic> json) => Host(
        id: json['id'] as String,
        label: json['label'] as String,
        hostname: json['hostname'] as String,
        port: (json['port'] as num?)?.toInt() ?? 22,
        username: json['username'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is Host &&
      other.id == id &&
      other.label == label &&
      other.hostname == hostname &&
      other.port == port &&
      other.username == username;

  @override
  int get hashCode => Object.hash(id, label, hostname, port, username);
}
