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
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../hosts/fingerprint.dart';
import '../hosts/host.dart';
import '../hosts/known_hosts.dart';
import '../keys/keystore_api.dart';
import 'connect_result.dart';
import 'keep_alive.dart';

const connectTimeout = Duration(seconds: 15);

/// Hard limit for the whole connect flow (socket, handshake, authentication),
/// not counting the time the user spends looking at the host key prompt.
const connectWatchdog = Duration(seconds: 30);

/// Asks the user whether to trust [key] for the first time. Must only return
/// true after an explicit "Trust" action. [serverClosed] completes if the
/// server closes the connection while the prompt is open, so the UI can say
/// so right away.
typedef TrustPrompt = Future<bool> Function(
  HostKey key,
  Future<void> serverClosed,
);

typedef SocketFactory = Future<SSHSocket> Function(
  String host,
  int port, {
  Duration? timeout,
});

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

class _Aborted implements Exception {
  const _Aborted();
}

/// Key login credentials. The private key never reaches this layer: [sign]
/// asks the Keystore (which asks the user) and returns the SSH signature blob.
class KeyAuth {
  const KeyAuth({
    required this.type,
    required this.publicKeyBlob,
    required this.sign,
    this.dismissPrompt,
  });

  /// `ecdsa-sha2-nistp256` or `ssh-ed25519`.
  final String type;
  final Uint8List publicKeyBlob;

  /// Returns the SSH signature blob for [data]. Throws [KeystoreException].
  final Future<Uint8List> Function(Uint8List data) sign;

  /// Closes the fingerprint prompt if the attempt ends while it is showing.
  final void Function()? dismissPrompt;
}

class _RawSignature implements SSHSignature {
  _RawSignature(this._bytes);
  final Uint8List _bytes;
  @override
  Uint8List encode() => _bytes;
}

/// Wraps the socket so that we see it closing (or failing) ourselves instead
/// of waiting for dartssh2 to notice.
class _WatchedSocket implements SSHSocket {
  _WatchedSocket(this._inner, this._onClosed) {
    _inner.done.then((_) => _onClosed(), onError: (Object _) => _onClosed());
  }

  final SSHSocket _inner;
  final void Function() _onClosed;

  @override
  late final Stream<Uint8List> stream = _inner.stream.transform(
    StreamTransformer<Uint8List, Uint8List>.fromHandlers(
      handleDone: (sink) {
        _onClosed();
        sink.close();
      },
      handleError: (error, stackTrace, sink) {
        _onClosed();
        sink.addError(error, stackTrace);
      },
    ),
  );

  @override
  StreamSink<List<int>> get sink => _inner.sink;

  @override
  Future<void> get done => _inner.done;

  @override
  Future<void> flush() => _inner.flush();

  @override
  Future<void> close() => _inner.close();

  @override
  void destroy() => _inner.destroy();
}

/// One SSH connection attempt to a [Host]. The password is passed to
/// [connect] only, used for authentication and never stored.
///
/// This class owns the connection lifetime: [connect] completes on the first
/// of success, a verdict on the host key, the socket closing, [cancel], or
/// the watchdog, whatever dartssh2 is doing. Everything it awaits can be
/// aborted by that.
class SshConnection {
  SshConnection({
    required this.host,
    required this.knownHosts,
    required this.onTrustPrompt,
    SocketFactory? socketFactory,
    this.watchdog = connectWatchdog,
    this.watchdogTick = const Duration(milliseconds: 250),
  }) : _socketFactory = socketFactory ?? SSHSocket.connect;

  final Host host;
  final KnownHostsStore knownHosts;
  final TrustPrompt onTrustPrompt;
  final SocketFactory _socketFactory;
  final Duration watchdog;
  final Duration watchdogTick;

  final _outcome = Completer<ConnectOutcome>();
  final _closedSignal = Completer<void>();
  SSHClient? _client;
  SessionKeepAlive? _keepAlive;
  SSHSocket? _socket;
  SSHSession? _session;
  KeyAuth? _keyAuth;
  Timer? _watchdogTimer;
  var _active = Duration.zero;
  var _prompting = false;
  HostKey? _pendingKey;
  HostKey? _presented;
  HostKey? _stored;
  ConnectResult _verdict = ConnectResult.trusted;

  /// Completes when the connection ends after [connect] succeeded.
  Future<void>? get done => _client?.done;

  SSHSession? get session => _session;

  /// For tests: whether a client or socket is still referenced.
  @visibleForTesting
  bool get holdsTransport => _client != null || _socket != null;

  /// True once [connect] has produced its outcome.
  bool get finished => _outcome.isCompleted;

  Future<ConnectOutcome> connect(String password) {
    unawaited(_start(password: password));
    return _outcome.future;
  }

  /// Logs in with a key instead of a password. There is no password fallback
  /// here: a rejected key ends as [ConnectResult.keyRejected].
  Future<ConnectOutcome> connectWithKey(KeyAuth key) {
    unawaited(_start(key: key));
    return _outcome.future;
  }

  /// Aborts the attempt: [connect] completes with [ConnectResult.cancelled]
  /// and the client and socket are closed right away.
  void cancel() => _finish(const ConnectOutcome(ConnectResult.cancelled));

  Future<T> _race<T>(Future<T> f) =>
      Future.any([f, _outcome.future.then<T>((_) => throw const _Aborted())]);

  Future<void> _start({String? password, KeyAuth? key}) async {
    _keyAuth = key;
    _watchdogTimer = Timer.periodic(watchdogTick, (_) {
      if (_prompting) return;
      _active += watchdogTick;
      if (_active >= watchdog) {
        _finish(
          const ConnectOutcome(
            ConnectResult.otherError,
            failure: ConnectFailure.timeout,
          ),
        );
      }
    });
    try {
      final storedKey = await _race(knownHosts.get(host.hostname, host.port));
      final socketFuture = _socketFactory(
        host.hostname,
        host.port,
        timeout: connectTimeout,
      );
      // A socket that arrives after we gave up must not leak.
      unawaited(
        socketFuture.then((s) {
          if (_outcome.isCompleted) s.destroy();
        }, onError: (Object _) {}),
      );
      final raw = await _race(socketFuture);
      if (_outcome.isCompleted) return;
      final socket = _WatchedSocket(raw, _onSocketClosed);
      _socket = socket;
      final client = SSHClient(
        socket,
        username: host.username,
        // Key login offers no password at all.
        onPasswordRequest: password == null ? null : () => password,
        identities: key == null ? null : [buildIdentity(key)],
        // dartssh2's own keep-alive is off: ours (SessionKeepAlive) times out
        // unanswered pings and ends a dead connection.
        keepAliveInterval: null,
        algorithms: SSHAlgorithms(
          hostkey: hostKeyPreference(storedType: storedKey?.type),
        ),
        onVerifyHostKey: verifyHostKey,
      );
      _client = client;
      _keepAlive = SessionKeepAlive(ping: client.ping, onDead: _closeTransport);
      // Errors surface through authenticated and the socket watcher below;
      // keep done from reporting them a second time as unhandled.
      unawaited(client.done.catchError((Object _) {}));
      await _race(client.authenticated);
      _finish(ConnectOutcome(_verdict, presentedKey: _presented));
    } on _Aborted {
      // Another path already completed the outcome.
    } catch (e) {
      _finish(_classify(e));
    }
  }

  /// The identity handed to dartssh2. Its signer never throws: dartssh2 awaits
  /// it in an un-awaited handler, where a thrown error would be unhandled and
  /// the authentication would just hang. Instead, every failure completes the
  /// connect outcome here and the signer returns a future that never
  /// completes (it references this connection, never the client).
  @visibleForTesting
  SSHIdentity buildIdentity(KeyAuth auth) => SSHIdentity.custom(
    type: auth.type,
    publicKey: SSHRawHostKey(auth.publicKeyBlob),
    // Ask the server first, so the fingerprint prompt only appears for a
    // key the server would accept.
    shouldProbe: true,
    signer: (data) => _signWithPrompt(auth, data),
  );

  Future<SSHSignature> _never() => Completer<SSHSignature>().future;

  Future<SSHSignature> _signWithPrompt(KeyAuth auth, Uint8List data) async {
    if (_outcome.isCompleted) return _never();
    // The user is at the fingerprint prompt: our watchdog must not run.
    _prompting = true;
    SSHSignature? signature;
    try {
      final blob = await _race(auth.sign(data));
      if (!_outcome.isCompleted) signature = _RawSignature(blob);
    } on _Aborted {
      // cancelled or timed out meanwhile: nothing more to do
    } on KeystoreException catch (e) {
      _finish(
        e.kind == KeystoreErrorKind.cancelled
            ? const ConnectOutcome(ConnectResult.cancelled)
            : ConnectOutcome(
                ConnectResult.otherError,
                failure: ConnectFailure.keyFailed,
                detail: e.message,
              ),
      );
    } catch (_) {
      _finish(
        const ConnectOutcome(
          ConnectResult.otherError,
          failure: ConnectFailure.keyFailed,
          detail: 'The key could not be used.',
        ),
      );
    } finally {
      _prompting = false;
    }
    return signature ?? _never();
  }

  void _onSocketClosed() {
    _finish(
      ConnectOutcome(
        ConnectResult.serverClosed,
        presentedKey: _presented,
        pendingKey: _prompting ? _pendingKey : null,
      ),
    );
  }

  /// First call wins. On anything but success the transport is closed.
  void _finish(ConnectOutcome outcome) {
    if (_outcome.isCompleted) return;
    _watchdogTimer?.cancel();
    if (outcome.result == ConnectResult.serverClosed &&
        !_closedSignal.isCompleted) {
      _closedSignal.complete();
    }
    _outcome.complete(outcome);
    if (outcome.connected) _keepAlive?.start();
    if (_prompting) _keyAuth?.dismissPrompt?.call();
    if (!outcome.connected) _closeTransport();
  }

  void _closeTransport() {
    _keepAlive?.stop();
    _keepAlive = null;
    _session = null;
    try {
      _client?.close();
    } catch (_) {}
    try {
      _socket?.destroy();
    } catch (_) {}
    _client = null;
    _socket = null;
  }

  /// dartssh2's host key callback. Public for tests.
  @visibleForTesting
  Future<bool> verifyHostKey(String type, Uint8List fingerprint) async {
    if (_outcome.isCompleted) return false;
    final key = HostKey(
      type: normalizeKeyType(type),
      fingerprint: fingerprintFromCallback(fingerprint),
    );
    _presented = key;
    final check = await knownHosts.check(host.hostname, host.port, key);
    if (_outcome.isCompleted) return false;
    switch (check.status) {
      case KnownHostStatus.match:
        _verdict = ConnectResult.trusted;
        return true;
      case KnownHostStatus.mismatch:
        _stored = check.stored;
        _finish(
          ConnectOutcome(
            ConnectResult.mismatch,
            storedKey: _stored,
            presentedKey: key,
          ),
        );
        return false;
      case KnownHostStatus.unknown:
        // The server is waiting while the user decides. Our watchdog pauses;
        // the server enforces its own grace time and our socket watcher tells
        // us (and the prompt) if it runs out.
        _prompting = true;
        _pendingKey = key;
        bool accepted;
        try {
          accepted = await onTrustPrompt(key, _closedSignal.future);
        } finally {
          _prompting = false;
        }
        if (accepted) {
          // The user verified the fingerprint the server actually presented,
          // so keep their decision even if the connection is already gone.
          await knownHosts.trust(host.hostname, host.port, key);
        }
        if (_outcome.isCompleted) return false;
        if (!accepted) {
          _finish(
            ConnectOutcome(ConnectResult.firstUseDeclined, presentedKey: key),
          );
          return false;
        }
        _pendingKey = null;
        _verdict = ConnectResult.firstUseAccepted;
        return true;
    }
  }

  /// Maps a dartssh2 error to our result. Public for tests.
  @visibleForTesting
  ConnectOutcome classifyError(Object error) => _classify(error);

  ConnectOutcome _classify(Object error) {
    if (error is SSHAuthAbortError) {
      // Authentication was cut short because the connection went away.
      return ConnectOutcome(
        ConnectResult.serverClosed,
        presentedKey: _presented,
      );
    }
    if (_keyAuth != null && error is SSHAuthFailError) {
      return ConnectOutcome(
        ConnectResult.keyRejected,
        presentedKey: _presented,
      );
    }
    final failure = switch (error) {
      TimeoutException() => ConnectFailure.timeout,
      SSHAuthError() => ConnectFailure.authFailed,
      SSHHostkeyError() => ConnectFailure.hostKeyRejected,
      SSHSocketError() || SocketException() => ConnectFailure.unreachable,
      _ => ConnectFailure.unknown,
    };
    return ConnectOutcome(
      ConnectResult.otherError,
      failure: failure,
      presentedKey: _presented,
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
    _watchdogTimer?.cancel();
    _closeTransport();
  }
}
