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
import '../../core/lock/app_lock_controller.dart';
import '../../core/ssh/ssh_connection.dart';
import '../../core/storage/terminal_settings.dart';
import '../theme.dart';
import '../lock/app_lock_gate.dart';
import '../private_input.dart';
import 'direct_input.dart';
import 'extra_keys.dart';
import 'pinch_zoom.dart';
import 'pty_resize.dart';

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
    this.onReconnect,
  });

  final Host host;
  final SshConnection connection;
  final TerminalSettings settings;

  /// Runs the full connect flow for [host] again (host key check, password or
  /// key prompt) and returns the new connection, or null if it did not
  /// connect. Null here means the banner has no Reconnect button.
  final Future<SshConnection?> Function(BuildContext context)? onReconnect;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with WidgetsBindingObserver {
  final _terminal = Terminal(maxLines: 10000);
  final _focus = FocusNode();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  var _ctrl = false;
  var _disconnected = false;
  String? _endMessage;

  var _fontSize = TerminalSettings.defaultFontSize;
  var _colors = TerminalColors.standard;
  var _inputMode = InputMode.direct;

  /// Direct input: the native keyboard view. Null in composing mode.
  DirectInput? _direct;
  var _resumed = true;
  AppLockController? _lock;

  var _barVisible = false;
  Timer? _barTimer;

  late SshConnection _conn = widget.connection;
  var _reconnecting = false;

  /// Resizes of the PTY are coalesced: none during a pinch, one at its end.
  late final _resizer = PtyResizeCoalescer(
    send: (columns, rows) => _conn.resize(columns, rows),
  );

  /// Typed input may reach the server only while the app is in front,
  /// unlocked, and the shell session is alive.
  bool get _acceptingInput =>
      _resumed &&
      !(_lock?.hidden ?? false) &&
      !_disconnected &&
      _conn.session != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(_syncInput);
    _direct = DirectInput(
      terminal: _terminal,
      accepting: () => _acceptingInput,
    );
    widget.settings.loadInputMode().then((mode) {
      if (!mounted) return;
      setState(() => _inputMode = mode);
      _syncInput();
    });
    _terminal.onOutput = _send;
    _terminal.onResize = (w, h, pw, ph) => _resizer.request(w, h);
    widget.settings.loadColors().then((colors) {
      if (mounted) setState(() => _colors = colors);
    });
    widget.settings.loadFontSize().then((size) {
      if (mounted) setState(() => _fontSize = size);
    });
    // Open the shell after the first layout so the PTY starts with the real
    // terminal size.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openShell());
  }

  /// Direct input follows the terminal's focus: attached while the terminal
  /// has focus and input is allowed, detached when a dialog or the lock cover
  /// takes over, the app is backgrounded, or the session ends.
  void _syncInput() {
    final direct = _direct;
    if (direct == null) return;
    if (_inputMode == InputMode.direct && _focus.hasFocus && _acceptingInput) {
      direct.attach();
    } else {
      direct.detach();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _syncInput();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lock = AppLockScope.maybeOf(context);
    if (!identical(lock, _lock)) {
      _lock?.removeListener(_syncInput);
      _lock = lock;
      _lock?.addListener(_syncInput);
    }
    _syncInput();
  }

  /// Written to the terminal between two sessions: closes whatever the old
  /// program left open (alternate screen, bracketed paste, mouse reporting,
  /// colors, hidden cursor) so the scrollback stays but the new shell starts
  /// clean, then a dim separator line.
  static const reconnectSeparator =
      '\x1b[0m\x1b[?1049l\x1b[?2004l\x1b[?1000l\x1b[?1002l\x1b[?1003l'
      '\x1b[?1006l\x1b[?25h\r\n\x1b[2m--- reconnected ---\x1b[0m\r\n';

  /// Runs the normal connect flow again. The old scrollback stays; on success
  /// a separator is printed and the new session continues below it.
  Future<void> _reconnect() async {
    final reconnect = widget.onReconnect;
    if (reconnect == null || _reconnecting || !_disconnected) return;
    _reconnecting = true;
    try {
      final fresh = await reconnect(context);
      if (fresh == null) return;
      if (!mounted) {
        fresh.close();
        return;
      }
      _conn.close();
      for (final s in _subscriptions) {
        s.cancel();
      }
      _subscriptions.clear();
      _terminal.write(reconnectSeparator);
      setState(() {
        _conn = fresh;
        _disconnected = false;
        _endMessage = null;
        _ctrl = false;
      });
      await _openShell();
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> _openShell() async {
    final conn = _conn;
    // A late event from a replaced connection must not end the new session.
    void ended(String message) {
      if (identical(conn, _conn)) _ended(message);
    }

    try {
      final columns = _terminal.viewWidth;
      final rows = _terminal.viewHeight;
      final session = await conn.openShell(columns, rows);
      _syncInput(); // there is a session now: input can be accepted
      _resizer.markSent(columns, rows); // the server has this size already
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
      unawaited(session.done.then((_) => ended('The session ended.')));
      unawaited(
        conn.done?.then(
          (_) => ended('The server closed the connection.'),
          onError: (_) => ended('The connection was lost.'),
        ),
      );
    } catch (_) {
      ended('Could not start a shell on the server.');
    }
  }

  void _ended(String message) {
    if (!mounted || _disconnected) return;
    setState(() {
      _disconnected = true;
      _endMessage = message;
    });
    _syncInput();
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
    WidgetsBinding.instance.removeObserver(this);
    _lock?.removeListener(_syncInput);
    _focus.removeListener(_syncInput);
    _direct?.dispose();
    _barTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _terminal.onOutput = null;
    _terminal.onResize = null;
    _resizer.dispose();
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
        backgroundColor: terminalThemeFor(_colors).background,
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
                      // The font changes on screen at every step; the server is
                      // told the new size once, when the fingers lift.
                      onChangeStart: _resizer.hold,
                      onChanged: (size) => setState(() => _fontSize = size),
                      onChangeEnd: (size) {
                        widget.settings.saveFontSize(size);
                        _resizer.release();
                      },
                      child: _TapToShowKeyboard(
                        enabled: _inputMode == InputMode.direct,
                        onTap: () => _direct?.attach(),
                        child: PrivateTerminalView(
                          _terminal,
                          focusNode: _focus,
                          hardwareKeyboardOnly: _inputMode == InputMode.direct,
                          textStyle: TerminalStyle(fontSize: _fontSize),
                          theme: terminalThemeFor(_colors),
                        ),
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
                          color: Colors.black,
                          shape: const Border(top: BorderSide(color: errorRed)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _endMessage ?? 'Disconnected',
                                    style: const TextStyle(color: errorRed),
                                  ),
                                ),
                                if (widget.onReconnect != null)
                                  TextButton(
                                    onPressed: _reconnect,
                                    child: const Text('Reconnect'),
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

/// In Direct input xterm opens no keyboard connection, so a tap on the
/// terminal brings the keyboard back (after it was hidden with Back).
class _TapToShowKeyboard extends StatefulWidget {
  const _TapToShowKeyboard({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_TapToShowKeyboard> createState() => _TapToShowKeyboardState();
}

class _TapToShowKeyboardState extends State<_TapToShowKeyboard> {
  final _down = <int, Offset>{};
  var _single = true;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (e) {
        if (_down.isNotEmpty) _single = false;
        _down[e.pointer] = e.position;
      },
      onPointerUp: (e) {
        final start = _down.remove(e.pointer);
        final tap =
            _single && start != null && (e.position - start).distance < 18;
        if (_down.isEmpty) _single = true;
        if (tap) widget.onTap();
      },
      onPointerCancel: (e) {
        _down.remove(e.pointer);
        if (_down.isEmpty) _single = true;
      },
      child: widget.child,
    );
  }
}
