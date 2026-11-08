// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../core/hosts/host.dart';
import '../../core/ssh/ssh_connection.dart';
import '../../core/storage/terminal_settings.dart';
import '../private_input.dart';
import 'extra_keys.dart';
import 'pinch_zoom.dart';

/// Converts a single typed character to its Ctrl-modified control character
/// (Ctrl+C -> 0x03, Ctrl+[ -> ESC, ...). Returns null if there is none.
String? applyCtrl(String data) {
  if (data.length != 1) return null;
  final c = data.codeUnitAt(0);
  if (c >= 0x61 && c <= 0x7a) return String.fromCharCode(c - 0x60); // a-z
  if (c >= 0x41 && c <= 0x5a) return String.fromCharCode(c - 0x40); // A-Z
  if (c >= 0x5b && c <= 0x5f) return String.fromCharCode(c - 0x40); // [\]^_
  if (c == 0x20 || c == 0x40) return '\x00'; // Ctrl+Space, Ctrl+@
  if (c == 0x3f) return '\x7f'; // Ctrl+?
  return null;
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({
    super.key,
    required this.host,
    required this.connection,
    required this.settings,
  });

  final Host host;
  final SshConnection connection;
  final TerminalSettings settings;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _terminal = Terminal(maxLines: 10000);
  final _focus = FocusNode();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  var _ctrl = false;
  var _disconnected = false;
  String? _endMessage;

  var _fontSize = TerminalSettings.defaultFontSize;

  var _barVisible = false;
  Timer? _barTimer;

  SshConnection get _conn => widget.connection;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = _send;
    _terminal.onResize = (w, h, pw, ph) => _conn.resize(w, h);
    widget.settings.loadFontSize().then((size) {
      if (mounted) setState(() => _fontSize = size);
    });
    // Open the shell after the first layout so the PTY starts with the real
    // terminal size.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openShell());
  }

  Future<void> _openShell() async {
    try {
      final session = await _conn.openShell(
        _terminal.viewWidth,
        _terminal.viewHeight,
      );
      _subscriptions
        ..add(
          session.stdout
              .cast<List<int>>()
              .transform(const Utf8Decoder(allowMalformed: true))
              .listen(_terminal.write),
        )
        ..add(
          session.stderr
              .cast<List<int>>()
              .transform(const Utf8Decoder(allowMalformed: true))
              .listen(_terminal.write),
        );
      unawaited(session.done.then((_) => _ended('The session ended.')));
      unawaited(
        _conn.done?.then(
          (_) => _ended('The server closed the connection.'),
          onError: (_) => _ended('The connection was lost.'),
        ),
      );
    } catch (_) {
      _ended('Could not start a shell on the server.');
    }
  }

  void _ended(String message) {
    if (!mounted || _disconnected) return;
    setState(() {
      _disconnected = true;
      _endMessage = message;
    });
  }

  void _send(String data) {
    if (_disconnected) return;
    var out = data;
    if (_ctrl) {
      out = applyCtrl(data) ?? data;
      setState(() => _ctrl = false);
    }
    _conn.session?.stdin.add(utf8.encode(out));
  }

  void _key(String name) {
    final ctrl = _ctrl;
    if (ctrl) setState(() => _ctrl = false);
    final key = switch (name) {
      'esc' => TerminalKey.escape,
      'tab' => TerminalKey.tab,
      'up' => TerminalKey.arrowUp,
      'down' => TerminalKey.arrowDown,
      'left' => TerminalKey.arrowLeft,
      _ => TerminalKey.arrowRight,
    };
    _terminal.keyInput(key, ctrl: ctrl);
    _focus.requestFocus();
  }

  void _text(String text) {
    _send(text);
    _focus.requestFocus();
  }

  void _showBar() {
    _barTimer?.cancel();
    setState(() => _barVisible = true);
    _barTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _barVisible = false);
    });
  }

  Future<void> _confirmDisconnect() async {
    if (_disconnected) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Disconnect?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _barTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _terminal.onOutput = null;
    _terminal.onResize = null;
    _conn.close();
    _focus.dispose();
    super.dispose();
  }

  Widget _disconnectButton() => IconButton(
    icon: const Icon(Icons.power_settings_new),
    tooltip: 'Disconnect',
    onPressed: _confirmDisconnect,
  );

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDisconnect();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // In landscape the app bar would eat a third of the height while the
        // keyboard is up, so it is hidden; tap the top edge to show it.
        appBar: landscape
            ? null
            : AppBar(
                title: Text(widget.host.label),
                backgroundColor: const Color(0xFF121212),
                actions: [_disconnectButton()],
              ),
        body: SafeArea(
          top: landscape,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    PinchZoom(
                      value: _fontSize,
                      onChanged: (size) => setState(() => _fontSize = size),
                      onChangeEnd: widget.settings.saveFontSize,
                      child: PrivateTerminalView(
                        _terminal,
                        focusNode: _focus,
                        textStyle: TerminalStyle(fontSize: _fontSize),
                      ),
                    ),
                    if (landscape) ...[
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 18,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _showBar,
                          child: const Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: EdgeInsets.only(top: 3),
                              child: SizedBox(
                                width: 36,
                                height: 3,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_barVisible)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: Material(
                            color: const Color(0xEE121212),
                            child: SizedBox(
                              height: 44,
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back),
                                    tooltip: 'Back',
                                    onPressed: _confirmDisconnect,
                                  ),
                                  Expanded(child: Text(widget.host.label)),
                                  _disconnectButton(),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                    if (_disconnected)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: const Color(0xFF7A1212),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(_endMessage ?? 'Disconnected'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ExtraKeysRow(
                ctrlActive: _ctrl,
                onCtrl: () {
                  setState(() => _ctrl = !_ctrl);
                  _focus.requestFocus();
                },
                onKey: _key,
                onText: _text,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
