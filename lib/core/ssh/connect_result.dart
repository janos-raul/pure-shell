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

  /// The server (or the network) closed the connection before we were
  /// connected. If that happened while the user was looking at the host key,
  /// [ConnectOutcome.pendingKey] holds that key.
  serverClosed,

  /// The user cancelled (including dismissing the fingerprint prompt).
  cancelled,

  /// Key login only: the server does not accept the key.
  keyRejected,

  /// Any other failure; see [ConnectFailure].
  otherError,
}

/// Cause of a [ConnectResult.otherError]. Each maps to a fixed user message;
/// raw exception text is never shown or logged.
enum ConnectFailure {
  timeout,
  unreachable,
  authFailed,
  hostKeyRejected,

  /// Key login: the key could not be used (lockout, invalidated, ...). The
  /// fixed user text is in [ConnectOutcome.detail].
  keyFailed,
  unknown,
}

class ConnectOutcome {
  const ConnectOutcome(
    this.result, {
    this.failure,
    this.storedKey,
    this.presentedKey,
    this.pendingKey,
    this.detail,
  });

  final ConnectResult result;
  final ConnectFailure? failure;

  /// For [ConnectResult.mismatch]: the previously trusted key.
  final HostKey? storedKey;

  /// For [ConnectResult.mismatch] and first use: the key the server presented.
  final HostKey? presentedKey;

  /// For [ConnectResult.serverClosed]: the key the user was still deciding on
  /// when the server closed the connection, if any.
  final HostKey? pendingKey;

  /// Fixed user-facing text for [ConnectFailure.keyFailed]; never raw error text.
  final String? detail;

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
  ConnectFailure.hostKeyRejected => 'The server host key was rejected.',
  ConnectFailure.keyFailed => 'The key could not be used.',
  ConnectFailure.unknown => 'The connection failed.',
};

const serverClosedMessage =
    'The server closed the connection. Please try again.';

const keyRejectedMessage = 'Server rejected the key.';

/// Shown under [keyRejectedMessage]: the server never says why, so this lists
/// where to look.
const keyRejectedHelp =
    "Check that this public key is in the user's ~/.ssh/authorized_keys "
    "(including any from= restriction), and see the server's auth log for "
    'the exact reason.';
