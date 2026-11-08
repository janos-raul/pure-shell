// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/hosts/host.dart';
import '../../core/hosts/known_hosts.dart';
import '../../core/ssh/connect_result.dart';
import '../../core/ssh/ssh_connection.dart';
import '../../core/storage/terminal_settings.dart';
import '../terminal/terminal_screen.dart';
import 'host_key_mismatch_screen.dart';

enum ConnectPhase { connecting, askTrust, trustedAfterClose }

/// State of the connect dialog. One dialog shows every phase, so there is
/// exactly one route to close and the wrong dialog can never be popped.
class ConnectController extends ChangeNotifier {
  ConnectController({required this.host, required this.knownHosts});

  final Host host;
  final KnownHostsStore knownHosts;

  ConnectPhase phase = ConnectPhase.connecting;
  HostKey? key;
  bool serverClosed = false;
  Completer<bool>? _decision;
  var _disposed = false;

  /// Handed to [SshConnection] as its TrustPrompt.
  Future<bool> askTrust(HostKey presented, Future<void> closed) {
    key = presented;
    serverClosed = false;
    phase = ConnectPhase.askTrust;
    final decision = _decision = Completer<bool>();
    closed.then((_) {
      if (_disposed || _decision != decision) return;
      serverClosed = true;
      notifyListeners();
    });
    notifyListeners();
    return decision.future;
  }

  /// The user tapped Trust. If the server has closed the connection already,
  /// the key is saved here (the user verified the fingerprint the server
  /// presented) and a reconnect is offered.
  Future<void> trust() async {
    if (serverClosed) {
      await knownHosts.trust(host.hostname, host.port, key!);
      phase = ConnectPhase.trustedAfterClose;
    } else {
      phase = ConnectPhase.connecting;
    }
    _complete(true);
    if (!_disposed) notifyListeners();
  }

  /// Cancel in the prompt: nothing is stored.
  void decline() => _complete(false);

  void _complete(bool accepted) {
    final d = _decision;
    _decision = null;
    if (d != null && !d.isCompleted) d.complete(accepted);
  }

  @override
  void dispose() {
    _disposed = true;
    _complete(false);
    super.dispose();
  }
}

class ConnectDialog extends StatelessWidget {
  const ConnectDialog({
    super.key,
    required this.controller,
    required this.host,
    required this.onCancel,
    required this.onReconnect,
  });

  final ConnectController controller;
  final Host host;
  final VoidCallback onCancel;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onCancel();
      },
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => switch (controller.phase) {
          ConnectPhase.connecting => AlertDialog(
            content: const Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Connecting...'),
              ],
            ),
            actions: [
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ),
          ConnectPhase.askTrust => _trustDialog(context),
          ConnectPhase.trustedAfterClose => AlertDialog(
            title: const Text('Host key trusted'),
            content: const Text(
              'The key was saved. The server had already closed the '
              'connection, so connect again to log in.',
            ),
            actions: [
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
              FilledButton(
                onPressed: onReconnect,
                child: const Text('Reconnect'),
              ),
            ],
          ),
        },
      ),
    );
  }

  Widget _trustDialog(BuildContext context) {
    final key = controller.key!;
    return AlertDialog(
      title: const Text('New host key'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('First connection to ${host.hostname}:${host.port}.'),
            const SizedBox(height: 12),
            const Text(
              'Key type',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(key.type),
            const SizedBox(height: 8),
            const Text(
              'SHA-256 fingerprint',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SelectableText(
              key.fingerprint,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Compare it with the fingerprint from your server '
              '(ssh-keygen -lf). The server only waits a limited time '
              'before closing the connection.',
            ),
            if (controller.serverClosed) ...[
              const SizedBox(height: 12),
              Text(
                'The server closed the connection while you were checking. '
                'If you trust this fingerprint, it is saved and you can '
                'reconnect.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
        FilledButton(onPressed: controller.trust, child: const Text('Trust')),
      ],
    );
  }
}

/// Password prompt. A stateful dialog owns its controller, so the controller
/// is only disposed once the dialog is really gone (not while it animates out).
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.host});

  final Host host;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.host.username}@${widget.host.hostname}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(labelText: 'Password'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

Future<String?> _askPassword(BuildContext context, Host host) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PasswordDialog(host: host),
    );

/// Password prompt, connect (with the one connect dialog), then the terminal
/// or the right error. The password only lives in this function's locals.
Future<void> connectToHost(
  BuildContext context, {
  required Host host,
  required KnownHostsStore knownHosts,
  required TerminalSettings settings,
  SocketFactory? socketFactory,
}) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  void snack(String message) =>
      messenger.showSnackBar(SnackBar(content: Text(message)));

  while (true) {
    final password = await _askPassword(context, host);
    if (password == null || !context.mounted) return;

    final controller = ConnectController(host: host, knownHosts: knownHosts);
    final conn = SshConnection(
      host: host,
      knownHosts: knownHosts,
      onTrustPrompt: controller.askTrust,
      socketFactory: socketFactory,
    );
    var reconnect = false;
    late final DialogRoute<void> route;
    void closeDialog() {
      if (route.isActive) navigator.removeRoute(route);
    }

    route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConnectDialog(
        controller: controller,
        host: host,
        onCancel: () {
          final inPrompt = controller.phase == ConnectPhase.askTrust;
          conn.cancel();
          controller.decline();
          closeDialog();
          if (inPrompt) snack('Host key not trusted. Connection cancelled.');
        },
        onReconnect: () {
          reconnect = true;
          closeDialog();
        },
      ),
    );
    unawaited(navigator.push(route));

    final outcome = await conn.connect(password);
    var keepDialog = false;
    switch (outcome.result) {
      case ConnectResult.trusted:
      case ConnectResult.firstUseAccepted:
        closeDialog();
        if (context.mounted) {
          await navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => TerminalScreen(
                host: host,
                connection: conn,
                settings: settings,
              ),
            ),
          );
        } else {
          conn.close();
        }
      case ConnectResult.mismatch:
        closeDialog();
        if (context.mounted) {
          await navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => HostKeyMismatchScreen(
                host: host,
                stored: outcome.storedKey,
                presented: outcome.presentedKey,
              ),
            ),
          );
        }
      case ConnectResult.firstUseDeclined:
      case ConnectResult.cancelled:
        closeDialog(); // the Cancel button already explained itself
      case ConnectResult.serverClosed:
        if (outcome.pendingKey != null) {
          // The Trust prompt is still open; it now says the server went away
          // and offers to save the key and reconnect.
          keepDialog = true;
        } else {
          closeDialog();
          snack(serverClosedMessage);
        }
      case ConnectResult.otherError:
        closeDialog();
        snack(connectFailureMessage(outcome.failure ?? ConnectFailure.unknown));
    }
    if (keepDialog) await route.completed;
    controller.dispose();
    if (!reconnect || !context.mounted) return;
  }
}
