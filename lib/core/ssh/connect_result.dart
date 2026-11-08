// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import '../hosts/known_hosts.dart';

/// How the host key check and connection attempt ended. The UI routes on this
/// enum, never on dartssh2's error text.
enum ConnectResult {
  /// Connected; the host key matched the stored one.
  trusted,

  /// Connected; first use, the user explicitly trusted the presented key.
  firstUseAccepted,

  /// First use and the user declined to trust the key. Nothing was stored.
  firstUseDeclined,

  /// The presented key differs from the stored one. Hard block.
  mismatch,

  /// Any other failure; see [ConnectFailure].
  otherError,
}

/// Cause of a [ConnectResult.otherError]. Each maps to a fixed user message;
/// raw exception text is never shown or logged.
enum ConnectFailure {
  timeout,
  unreachable,
  authFailed,

  /// The server dropped the connection while we waited for the user to decide
  /// on the host key (sshd LoginGraceTime, 120 s by default).
  serverClosedDuringPrompt,
  serverClosed,
  hostKeyRejected,
  unknown,
}

class ConnectOutcome {
  const ConnectOutcome(
    this.result, {
    this.failure,
    this.storedKey,
    this.presentedKey,
  });

  final ConnectResult result;
  final ConnectFailure? failure;

  /// For [ConnectResult.mismatch]: the previously trusted key.
  final HostKey? storedKey;

  /// For [ConnectResult.mismatch] and first use: the key the server presented.
  final HostKey? presentedKey;

  bool get connected =>
      result == ConnectResult.trusted ||
      result == ConnectResult.firstUseAccepted;
}

String connectFailureMessage(ConnectFailure failure) => switch (failure) {
      ConnectFailure.timeout =>
        'The server did not respond in time. Check the address and your network.',
      ConnectFailure.unreachable =>
        'Could not reach the server. Check the hostname, port and your network.',
      ConnectFailure.authFailed =>
        'Authentication failed. Check the username and password.',
      ConnectFailure.serverClosedDuringPrompt =>
        'The server closed the connection while you were deciding. '
            'Servers drop idle logins after about two minutes. Please try again.',
      ConnectFailure.serverClosed =>
        'The server closed the connection. Please try again.',
      ConnectFailure.hostKeyRejected =>
        'The server host key was rejected.',
      ConnectFailure.unknown => 'The connection failed.',
    };
