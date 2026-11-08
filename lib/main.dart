// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';

void main() {
  runApp(const PureShellApp());
}

class PureShellApp extends StatelessWidget {
  const PureShellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PureShell',
      theme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(body: Center(child: Text('PureShell'))),
    );
  }
}
