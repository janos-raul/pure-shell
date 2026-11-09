// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

/// The command to run on the server to print the fingerprint of its host key
/// of the given SSH key [type] (as in the first-connect prompt), so it can be
/// compared with what PureShell shows. Modern ssh-keygen prints SHA-256 by
/// default, the same format PureShell shows.
String hostKeyCheckCommand(String type) {
  final file = switch (type) {
    'ssh-ed25519' => 'ssh_host_ed25519_key.pub',
    'ssh-rsa' => 'ssh_host_rsa_key.pub',
    _ when type.startsWith('ecdsa-sha2-') => 'ssh_host_ecdsa_key.pub',
    _ => null,
  };
  return file == null
      ? 'ssh-keygen -lf /etc/ssh/ssh_host_*_key.pub'
      : 'ssh-keygen -lf /etc/ssh/$file';
}
