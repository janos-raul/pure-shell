// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:dartssh2/dartssh2.dart';

import '../hosts/fingerprint.dart';
import '../hosts/host.dart';
import '../hosts/known_hosts.dart';
import 'connect_result.dart';

const connectTimeout = Duration(seconds: 15);
const keepAliveInterval = Duration(seconds: 30);

/// Asks the user whether to trust [key] for the first time. Must only return
/// true after an explicit "Trust" action.
typedef TrustPrompt = Future<bool> Function(HostKey key);

/// Maps dartssh2's negotiated signature algorithm to the key type we store.
/// An RSA key can be presented as ssh-rsa, rsa-sha2-256 or rsa-sha2-512; these
/// are the same key and must not cause a false mismatch.
String normalizeKeyType(String negotiated) => switch (negotiated) {
  'rsa-sha2-256' || 'rsa-sha2-512' => 'ssh-rsa',
  _ => negotiated,
};

/// Host key algorithm preference. The order is fixed in our code (the same as
/// dartssh2's modern defaults, legacy SHA-1 RSA excluded). If a key type is
/// already trusted for the host, its algorithms are moved to the front, as
/// OpenSSH does, so a known server keeps presenting the known key type.
List<SSHHostkeyType> hostKeyPreference({String? storedType}) {
  const base = [
    SSHHostkeyType.ed25519,
    SSHHostkeyType.rsaSha512,
    SSHHostkeyType.rsaSha256,
    SSHHostkeyType.ecdsa521,
    SSHHostkeyType.ecdsa384,
    SSHHostkeyType.ecdsa256,
  ];
  if (storedType == null) return base;
  final preferred = base
      .where((a) => normalizeKeyType(a.name) == storedType)
      .toList();
  return [...preferred, ...base.where((a) => !preferred.contains(a))];
}

/// One SSH connection attempt to a [Host]. The password is passed to
/// [connect] only, used for authentication and never stored.
class SshConnection {
  SshConnection({
    required this.host,
    required this.knownHosts,
    required this.onTrustPrompt,
  });

  final Host host;
  final KnownHostsStore knownHosts;
  final TrustPrompt onTrustPrompt;

  SSHClient? _client;
  SSHSession? _session;

  /// Completes when the connection ends after [connect] succeeded.
  Future<void>? get done => _client?.done;

  SSHSession? get session => _session;

  Future<ConnectOutcome> connect(String password) async {
    var result = ConnectResult.otherError;
    HostKey? stored;
    HostKey? presented;
    var prompted = false;
    Timer? timer;
    final deadline = Completer<void>();

    void startTimer() {
      timer?.cancel();
      timer = Timer(connectTimeout, () {
        if (!deadline.isCompleted) deadline.complete();
      });
    }

    try {
      startTimer();
      final storedKey = await knownHosts.get(host.hostname, host.port);
      final socket = await SSHSocket.connect(
        host.hostname,
        host.port,
        timeout: connectTimeout,
      );

      final client = SSHClient(
        socket,
        username: host.username,
        onPasswordRequest: () => password,
        keepAliveInterval: keepAliveInterval,
        algorithms: SSHAlgorithms(
          hostkey: hostKeyPreference(storedType: storedKey?.type),
        ),
        onVerifyHostKey: (type, fingerprint) async {
          final key = HostKey(
            type: normalizeKeyType(type),
            fingerprint: fingerprintFromCallback(fingerprint),
          );
          presented = key;
          final check = await knownHosts.check(host.hostname, host.port, key);
          switch (check.status) {
            case KnownHostStatus.match:
              result = ConnectResult.trusted;
              return true;
            case KnownHostStatus.mismatch:
              stored = check.stored;
              result = ConnectResult.mismatch;
              return false;
            case KnownHostStatus.unknown:
              // The server is waiting while the user decides: pause our own
              // timeout, the server enforces its own grace time.
              timer?.cancel();
              prompted = true;
              final accepted = await onTrustPrompt(key);
              if (!accepted) {
                result = ConnectResult.firstUseDeclined;
                return false;
              }
              await knownHosts.trust(host.hostname, host.port, key);
              result = ConnectResult.firstUseAccepted;
              startTimer();
              return true;
          }
        },
      );
      _client = client;

      // Keep the failure of the handshake from being reported twice.
      unawaited(client.done.catchError((_) {}));
      await Future.any([
        client.authenticated,
        deadline.future.then((_) => throw TimeoutException('connect')),
      ]);
      timer?.cancel();
      return ConnectOutcome(result, presentedKey: presented);
    } catch (e) {
      timer?.cancel();
      close();
      return _classify(e, result, stored, presented, prompted);
    }
  }

  ConnectOutcome _classify(
    Object error,
    ConnectResult result,
    HostKey? stored,
    HostKey? presented,
    bool prompted,
  ) {
    // Our own verdict from the host key callback wins over whatever generic
    // error dartssh2 raised when we refused the key.
    if (result == ConnectResult.mismatch) {
      return ConnectOutcome(
        ConnectResult.mismatch,
        storedKey: stored,
        presentedKey: presented,
      );
    }
    if (result == ConnectResult.firstUseDeclined) {
      return ConnectOutcome(
        ConnectResult.firstUseDeclined,
        presentedKey: presented,
      );
    }
    ConnectFailure failure;
    if (error is TimeoutException) {
      failure = ConnectFailure.timeout;
    } else if (error is SSHAuthError) {
      failure = ConnectFailure.authFailed;
    } else if (error is SSHHostkeyError) {
      failure = ConnectFailure.hostKeyRejected;
    } else if (prompted) {
      failure = ConnectFailure.serverClosedDuringPrompt;
    } else if (error is SSHSocketError || error is SocketException) {
      failure = ConnectFailure.unreachable;
    } else if (error is SSHDisconnectError) {
      failure = ConnectFailure.serverClosed;
    } else {
      failure = ConnectFailure.unknown;
    }
    return ConnectOutcome(
      ConnectResult.otherError,
      failure: failure,
      presentedKey: presented,
    );
  }

  /// Starts the interactive shell with a PTY of the given size.
  Future<SSHSession> openShell(int columns, int rows) async {
    final client = _client!;
    final session = await client.shell(
      pty: SSHPtyConfig(type: 'xterm-256color', width: columns, height: rows),
    );
    _session = session;
    return session;
  }

  /// Forwards a terminal resize to the server.
  void resize(int columns, int rows) {
    if (columns > 0 && rows > 0) _session?.resizeTerminal(columns, rows);
  }

  void close() {
    _session = null;
    _client?.close();
    _client = null;
  }
}
