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

import 'package:flutter/services.dart';

import '../../core/hosts/host.dart';
import '../../core/platform_support.dart';
import '../../core/lock/app_lock_controller.dart';
import '../../core/ssh/session_keeper.dart';
import '../../core/ssh/ssh_connection.dart';
import '../../core/storage/terminal_settings.dart';
import '../theme.dart';
import '../lock/app_lock_gate.dart';
import '../private_input.dart';
import 'command_box.dart';
import 'desktop_keys.dart';
import 'direct_input.dart';
import 'extra_keys.dart';
import 'pinch_zoom.dart';
import 'pty_resize.dart';
import 'terminal_clipboard.dart';

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
  final _termController = TerminalController();
  final _clipboard = TerminalClipboard();
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

  /// The command-line box. Its text lives only in this controller and is
  /// cleared whenever the box closes, the app is covered, or the session ends.
  final _boxText = TextEditingController();
  final _boxFocus = FocusNode();
  var _boxOpen = false;
  var _boxKeepOpen = false;
  var _boxPrevLength = 0;

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
  bool get _sessionLive =>
      _resumed &&
      !(_lock?.hidden ?? false) &&
      !_disconnected &&
      _conn.session != null;

  /// Not backgrounded and not under the lock cover: copy and paste are off
  /// otherwise, like typed input.
  bool get _visibleToUser => _resumed && !(_lock?.hidden ?? false);

  /// Same, and the native Direct-mode view is the one meant to be typing: not
  /// while the command-line box has the keyboard.
  bool get _acceptingInput => _sessionLive && !_boxOpen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(_syncInput);
    // Desktop: no native keyboard view; xterm's own text input client takes
    // keys, IME composition and typed text (emoji panel, remote desktop).
    _direct = windowsStub
        ? null
        : DirectInput(terminal: _terminal, accepting: () => _acceptingInput);
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
    // Covered, backgrounded or ended: the box and its text go away first.
    if (_boxOpen && (!_resumed || (_lock?.hidden ?? false) || _disconnected)) {
      _closeBox();
    }
    final direct = _direct;
    if (direct == null) return;
    if (_inputMode == InputMode.direct && _focus.hasFocus && _acceptingInput) {
      direct.attach();
    } else {
      // With the box open the keyboard stays up: it moves to the box's field.
      direct.detach(hide: !_boxOpen);
    }
  }

  void _toggleBox() {
    if (_boxOpen) {
      _closeBox();
    } else if (_sessionLive) {
      setState(() {
        _ctrl = false; // sticky Ctrl is released when the box opens
        _boxOpen = true;
        _boxPrevLength = 0;
      });
      // The native view lets go of the keyboard (without hiding it) and the
      // box's field takes the focus, so the keyboard connects to it. (Not
      // autofocus: that does nothing while the terminal holds the focus.)
      _syncInput();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _boxOpen) _boxFocus.requestFocus();
      });
    }
  }

  void _closeBox() {
    if (!_boxOpen) return;
    _boxText.clear();
    _boxPrevLength = 0;
    if (mounted) setState(() => _boxOpen = false);
    _boxOpen = false;
    _boxFocus.unfocus();
    _focus.requestFocus();
    // Once the field is gone the native view takes the keyboard back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncInput();
    });
    _syncInput();
  }

  /// A typed Enter at the very end of the box sends (the box is not
  /// single-line, so the keyboard inserts a line break instead).
  void _onBoxChanged(String text) {
    final sel = _boxText.selection;
    if (text.length == _boxPrevLength + 1 &&
        text.endsWith('\n') &&
        sel.isCollapsed &&
        sel.baseOffset == text.length) {
      _boxText.text = text.substring(0, text.length - 1);
      _sendBox();
      return;
    }
    _boxPrevLength = text.length;
  }

  /// Single-line text is sent with Enter; text with line breaks is a paste
  /// (bracketed when the program asked for it) with no Enter added.
  void _sendBox() {
    if (!_sessionLive) {
      _closeBox();
      return;
    }
    final text = _boxText.text;
    if (text.contains('\n') || text.contains('\r')) {
      _terminal.paste(text.replaceAll('\r\n', '\r').replaceAll('\n', '\r'));
    } else {
      _send('$text\r');
    }
    _boxText.clear();
    _boxPrevLength = 0;
    if (!_boxKeepOpen) {
      _closeBox();
    } else {
      _boxFocus.requestFocus();
    }
  }

  /// Extra keys while the box is open: they act on the box only.
  void _boxKey(String name) {
    final text = _boxText.text;
    final at = _boxText.selection.isValid
        ? _boxText.selection.extentOffset
        : text.length;
    final to = switch (name) {
      'esc' => null,
      'left' => moveCaret(text, at, dx: -1),
      'right' => moveCaret(text, at, dx: 1),
      'up' => moveCaret(text, at, dy: -1),
      'down' => moveCaret(text, at, dy: 1),
      _ => at,
    };
    if (name == 'esc') {
      _closeBox();
    } else if (to != null) {
      _boxText.selection = TextSelection.collapsed(offset: to);
      _boxFocus.requestFocus();
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
      if (!mounted || !identical(conn, _conn)) return;
      // Counted for the keep-alive notification; "Disconnect all" ends it.
      unawaited(
        SessionKeeper.instance.opened(this, _disconnectFromNotification),
      );
      unawaited(_maybeAskNotifications());
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

  /// "Disconnect all" in the notification: works without unlocking.
  void _disconnectFromNotification() {
    if (!mounted || _disconnected) return;
    _ended('Disconnected from the notification.');
    _conn.close();
  }

  /// After the first connect: explain the notification once, then ask for the
  /// permission (Android 13+). Never blocks; "Not now" is fine, the service
  /// still keeps the sessions alive, only its notification is hidden.
  Future<void> _maybeAskNotifications() async {
    final keeper = SessionKeeper.instance;
    if (!keeper.enabled) return;
    if (await widget.settings.loadNotificationAsked()) return;
    if (await keeper.notificationsAllowed()) return;
    if (!mounted || !_sessionLive) return;
    await widget.settings.saveNotificationAsked();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Keep sessions alive'),
        content: const Text(
          'While you are connected, Pure-Shell shows a notification with the '
          'number of sessions, so Android does not cut them a few seconds '
          'after you leave the app. It never shows hostnames, usernames or '
          'terminal content.\n\nAndroid will ask to allow notifications. '
          'You can say no: sessions are still kept alive, just without the '
          'notification.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok == true) await keeper.requestNotifications();
  }

  void _ended(String message) {
    if (!mounted || _disconnected) return;
    unawaited(SessionKeeper.instance.closed(this));
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
    if (_boxOpen) {
      _boxKey(name);
      return;
    }
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
    if (_boxOpen) {
      insertAtCursor(_boxText, text);
      _boxPrevLength = _boxText.text.length;
      _boxFocus.requestFocus();
      return;
    }
    _send(text);
    _focus.requestFocus();
  }

  /// Paste from the clipboard (read now, because the user asked; never
  /// before). With the box open it goes into the box, otherwise to the
  /// session through the terminal's paste path: bracketed when the program
  /// asked for it, so multi-line text does not run line by line.
  Future<void> _paste() async {
    if (!_sessionLive) return;
    final raw = await _clipboard.readText();
    // The app may have been covered or the session may have ended meanwhile.
    if (raw == null || raw.isEmpty || !mounted || !_sessionLive) return;
    final text = sanitizePaste(raw);
    if (text.isEmpty) return;
    if (_ctrl) setState(() => _ctrl = false); // a paste is not Ctrl+key
    if (_boxOpen) {
      insertAtCursor(_boxText, text.replaceAll('\r', '\n'));
      _boxPrevLength = _boxText.text.length;
      _boxFocus.requestFocus();
      return;
    }
    if (text.contains('\r') && !_terminal.bracketedPasteMode) {
      // This program did not ask for bracketed paste: each line would be
      // entered as typed. Make the user say yes.
      final lines = '\r'.allMatches(text).length + 1;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Paste $lines lines?'),
          content: const Text(
            'This program did not ask for bracketed paste, so every line '
            'break acts as Enter and each line runs as it is entered.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Paste'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted || !_sessionLive) return;
    }
    _terminal.paste(text);
    if (!_boxOpen) _focus.requestFocus();
  }

  Future<void> _copySelection() async {
    final range = _termController.selection;
    if (range == null || !_visibleToUser) return;
    final text = _terminal.buffer.getText(range);
    if (text.isEmpty) return;
    await _clipboard.copySensitive(text);
  }

  /// Desktop shortcuts, before xterm (see [desktopKeyAction]). Anything not
  /// listed there goes to the shell unchanged.
  KeyEventResult _onDesktopKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final action = desktopKeyAction(
      event.logicalKey,
      ctrl: keys.isControlPressed,
      shift: keys.isShiftPressed,
      alt: keys.isAltPressed,
      character: event.character,
    );
    switch (action) {
      case null:
        return KeyEventResult.ignored;
      case CopyAction():
        unawaited(_copySelection());
      case PasteAction():
        unawaited(_paste());
      case ZoomAction():
        return KeyEventResult.ignored; // font zoom: not wired up yet
      case TypeAction(:final text):
        if (_sessionLive) _terminal.textInput(text);
    }
    return KeyEventResult.handled;
  }

  void _selectAll() {
    if (!_visibleToUser) return;
    final b = _terminal.buffer;
    _termController.setSelection(
      b.createAnchor(0, 0),
      b.createAnchor(_terminal.viewWidth, b.height - 1),
    );
  }

  /// Long press on the terminal: Paste always; Copy and Select all when
  /// something is selected (the long press itself selects a word).
  Future<void> _showTextMenu(Offset position) async {
    final selected = _termController.selection != null;
    final visible = _visibleToUser;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'paste',
          enabled: visible && _sessionLive,
          child: const Text('Paste'),
        ),
        if (selected) ...[
          PopupMenuItem(
            value: 'copy',
            enabled: visible,
            child: const Text('Copy'),
          ),
          PopupMenuItem(
            value: 'all',
            enabled: visible,
            child: const Text('Select all'),
          ),
        ],
      ],
    );
    // Each action checks again: the menu may have been open while the app
    // was locked.
    switch (choice) {
      case 'paste':
        await _paste();
      case 'copy':
        await _copySelection();
      case 'all':
        _selectAll();
    }
  }

  /// Right-click on the desktop: Copy (only with a selection), Paste, Select
  /// all, Clear selection. Paste takes the same cleaned path as everywhere.
  Future<void> _showContextMenu(Offset position) async {
    final selected = _termController.selection != null;
    final visible = _visibleToUser;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        if (selected)
          PopupMenuItem(
            value: 'copy',
            enabled: visible,
            child: const _MenuEntry('Copy', 'Ctrl+Shift+C'),
          ),
        PopupMenuItem(
          value: 'paste',
          enabled: visible && _sessionLive,
          child: const _MenuEntry('Paste', 'Ctrl+Shift+V'),
        ),
        PopupMenuItem(
          value: 'all',
          enabled: visible,
          child: const Text('Select all'),
        ),
        if (selected)
          const PopupMenuItem(value: 'clear', child: Text('Clear selection')),
      ],
    );
    switch (choice) {
      case 'copy':
        await _copySelection();
      case 'paste':
        await _paste();
      case 'all':
        _selectAll();
      case 'clear':
        _termController.clearSelection();
    }
    if (mounted) _focus.requestFocus();
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
          FilledButton(
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
    unawaited(SessionKeeper.instance.closed(this));
    _direct?.dispose();
    _boxText.dispose();
    _termController.dispose();
    _boxFocus.dispose();
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
                      child: _LongPress(
                        onLongPress: _showTextMenu,
                        child: _TapToShowKeyboard(
                          enabled:
                              !windowsStub && _inputMode == InputMode.direct,
                          onTap: () => _direct?.attach(),
                          child: PrivateTerminalView(
                            _terminal,
                            controller: _termController,
                            focusNode: _focus,
                            hardwareKeyboardOnly:
                                !windowsStub && _inputMode == InputMode.direct,
                            // Desktop: no xterm shortcuts (they took Ctrl+A
                            // and Ctrl+V from the shell); ours run first.
                            shortcuts: windowsStub ? const {} : null,
                            onKeyEvent: windowsStub ? _onDesktopKey : null,
                            onSecondaryTapDown: windowsStub
                                ? (d, _) => _showContextMenu(d.globalPosition)
                                : null,
                            textStyle: TerminalStyle(fontSize: _fontSize),
                            theme: terminalThemeFor(_colors),
                          ),
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
                // Nothing to send to once the session is over.
                enabled: !_disconnected,
                boxOpen: _boxOpen,
                onBox: _toggleBox,
                onPaste: _paste,
              ),
              if (_boxOpen)
                CommandLineBox(
                  controller: _boxText,
                  focusNode: _boxFocus,
                  keepOpen: _boxKeepOpen,
                  onKeepOpenChanged: (v) => setState(() => _boxKeepOpen = v),
                  onChanged: _onBoxChanged,
                  onSend: _sendBox,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A context menu entry with its shortcut on the right.
class _MenuEntry extends StatelessWidget {
  const _MenuEntry(this.label, this.shortcut);

  final String label;
  final String shortcut;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      const SizedBox(width: 24),
      Text(
        shortcut,
        style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
      ),
    ],
  );
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

/// Reports a long press (one finger held still) without taking part in the
/// gesture arena, so the terminal's own long-press word selection still runs
/// first; the callback fires a little after it.
class _LongPress extends StatefulWidget {
  const _LongPress({required this.onLongPress, required this.child});

  final void Function(Offset globalPosition) onLongPress;
  final Widget child;

  @override
  State<_LongPress> createState() => _LongPressState();
}

class _LongPressState extends State<_LongPress> {
  Timer? _timer;
  int? _pointer;
  Offset _start = Offset.zero;

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _pointer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        if (_pointer != null) {
          _cancel(); // a second finger: pinch, not a long press
          return;
        }
        _pointer = e.pointer;
        _start = e.position;
        _timer = Timer(const Duration(milliseconds: 650), () {
          final at = _start;
          _cancel();
          widget.onLongPress(at);
        });
      },
      onPointerMove: (e) {
        if (e.pointer == _pointer && (e.position - _start).distance > 18) {
          _cancel();
        }
      },
      onPointerUp: (e) {
        if (e.pointer == _pointer) _cancel();
      },
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _cancel();
      },
      child: widget.child,
    );
  }
}
