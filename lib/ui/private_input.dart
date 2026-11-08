// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Text fields that ask the keyboard not to learn from, store or "fix" what is
/// typed: no personalized learning (IME_FLAG_NO_PERSONALIZED_LEARNING on
/// Android), no suggestions, no autocorrect, no smart dashes or quotes.
///
/// This is a request to the keyboard app; third-party keyboards may ignore it.
class PrivateTextFormField extends StatelessWidget {
  const PrivateTextFormField({
    super.key,
    this.controller,
    this.decoration,
    this.keyboardType,
    this.validator,
    this.textInputAction,
    this.obscureText = false,
    this.autofocus = false,
    this.onFieldSubmitted,
  });

  final TextEditingController? controller;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool autofocus;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: decoration,
      keyboardType: keyboardType,
      validator: validator,
      textInputAction: textInputAction,
      obscureText: obscureText,
      autofocus: autofocus,
      onFieldSubmitted: onFieldSubmitted,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
    );
  }
}

/// The terminal view with the keyboard settings pinned in our code.
///
/// xterm 4.0.0 itself sends `autocorrect: false`, `enableSuggestions: false`
/// and `enableIMEPersonalizedLearning: false` to the keyboard (it does not
/// expose them, and does not set smart dashes/quotes). We pin the keyboard
/// type explicitly (not `visiblePassword`, which some keyboards, Samsung's
/// especially, answer with a different layout) and a test checks what xterm
/// actually sends, so an xterm update cannot silently drop these flags.
class PrivateTerminalView extends StatelessWidget {
  const PrivateTerminalView(
    this.terminal, {
    super.key,
    required this.focusNode,
    required this.textStyle,
    this.autofocus = true,
  });

  final Terminal terminal;
  final FocusNode focusNode;
  final TerminalStyle textStyle;
  final bool autofocus;

  /// The keyboard type we ask for.
  static const keyboardType = TextInputType.emailAddress;

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      terminal,
      focusNode: focusNode,
      autofocus: autofocus,
      hardwareKeyboardOnly: false,
      keyboardType: keyboardType,
      backgroundOpacity: 1,
      textStyle: textStyle,
    );
  }
}
