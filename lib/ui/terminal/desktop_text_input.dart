// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Desktop text input for the terminal: everything that arrives as text and
/// not as a key press, i.e. IME composition, the emoji panel (Win+.) and
/// text injected by remote-desktop or automation tools.
///
/// Key presses themselves are handled by xterm's hardware-keyboard listener,
/// which types a key's character and marks the event handled, so Windows does
/// not deliver the same character here a second time.
///
/// Why not xterm's own text input client: it attaches without a view ID,
/// which Flutter on Windows rejects ("Could not set client, view ID is
/// null"), so no text ever arrived.
class DesktopTextInput extends StatefulWidget {
  const DesktopTextInput({
    super.key,
    required this.focusNode,
    required this.enabled,
    required this.onText,
    required this.onComposing,
    required this.child,
    this.viewKey,
  });

  final FocusNode focusNode;

  /// Whether text may reach the session now (attached only while true and
  /// the terminal has the focus).
  final bool enabled;

  /// Committed text: send it to the session.
  final ValueChanged<String> onText;

  /// The IME composition in progress (null when there is none).
  final ValueChanged<String?> onComposing;

  /// For placing the IME candidate window at the terminal cursor.
  final GlobalKey<TerminalViewState>? viewKey;

  final Widget child;

  @override
  State<DesktopTextInput> createState() => DesktopTextInputState();
}

@visibleForTesting
class DesktopTextInputState extends State<DesktopTextInput>
    with TextInputClient {
  static const _empty = TextEditingValue(
    selection: TextSelection.collapsed(offset: 0),
  );

  TextInputConnection? _connection;
  var _value = _empty;

  bool get attached => _connection?.attached ?? false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(DesktopTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_sync);
      widget.focusNode.addListener(_sync);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_sync);
    _close();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    if (widget.enabled && widget.focusNode.hasFocus) {
      _open();
    } else {
      _close();
    }
  }

  void _open() {
    if (attached) {
      _updateGeometry();
      return;
    }
    _value = _empty;
    _connection = TextInput.attach(
      this,
      TextInputConfiguration(
        viewId: View.of(context).viewId,
        inputAction: TextInputAction.none,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
      ),
    )..show();
    _connection!.setEditingState(_value);
    _updateGeometry();
  }

  void _close() {
    if (_connection == null) return;
    if (attached) _connection!.close();
    _connection = null;
    widget.onComposing(null);
  }

  /// Tells Windows where the terminal cursor is, for the IME window.
  void _updateGeometry() {
    final view = widget.viewKey?.currentState;
    final conn = _connection;
    if (view == null || conn == null || !attached) return;
    try {
      final box = view.renderTerminal;
      if (!box.attached || !box.hasSize) return;
      conn.setEditableSizeAndTransform(box.size, box.getTransformTo(null));
      conn.setCaretRect(view.cursorRect);
    } catch (_) {
      // Not laid out yet: the IME window just opens at its default place.
    }
  }

  @override
  TextEditingValue? get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    _value = value;
    final composing = value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      widget.onComposing(composing.textInside(value.text));
      _updateGeometry();
      return;
    }
    widget.onComposing(null);
    if (value.text.isNotEmpty) {
      widget.onText(value.text);
      _value = _empty;
      _connection?.setEditingState(_empty);
    }
    _updateGeometry();
  }

  @override
  void performAction(TextInputAction action) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
    widget.onComposing(null);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
