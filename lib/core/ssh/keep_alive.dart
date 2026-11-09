// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';

/// How often an idle session is pinged. Frequent enough to keep a home
/// router's or carrier's NAT entry alive, rare enough to cost no noticeable
/// battery.
const keepAliveInterval = Duration(seconds: 30);

/// How long one ping may wait for the server's reply.
const keepAliveReplyTimeout = Duration(seconds: 15);

/// How many pings in a row may go unanswered before the connection is
/// declared dead (about interval + timeout per miss: ~1.5 minutes in all).
const keepAliveMaxMissed = 2;

/// Pings the server regularly and reports a connection that stopped answering.
///
/// dartssh2's own keep-alive sends the pings but ignores failures and has no
/// timeout, so a path that silently died (NAT entry dropped, Wi-Fi gone) is
/// only noticed when TCP gives up, which can take many minutes. This one calls
/// [onDead] after [maxMissed] unanswered pings.
class SessionKeepAlive {
  SessionKeepAlive({
    required this.ping,
    required this.onDead,
    this.interval = keepAliveInterval,
    this.replyTimeout = keepAliveReplyTimeout,
    this.maxMissed = keepAliveMaxMissed,
  });

  /// Sends one keep-alive and completes when the server answered.
  final Future<void> Function() ping;

  /// Called once, when [maxMissed] pings in a row got no answer.
  final void Function() onDead;

  final Duration interval;
  final Duration replyTimeout;
  final int maxMissed;

  Timer? _timer;
  var _pinging = false;
  var _missed = 0;

  bool get running => _timer != null;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _missed = 0;
  }

  Future<void> _tick() async {
    if (_pinging) return;
    _pinging = true;
    try {
      await ping().timeout(replyTimeout);
      _missed = 0;
    } catch (_) {
      if (++_missed >= maxMissed && running) {
        stop();
        onDead();
      }
    } finally {
      _pinging = false;
    }
  }
}
