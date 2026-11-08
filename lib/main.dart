// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/material.dart';

import 'core/hosts/host_repository.dart';
import 'core/hosts/known_hosts.dart';
import 'core/storage/secure_store.dart';
import 'ui/hosts/host_list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = FlutterSecureStore();
  final knownHosts = KnownHostsStore(store);
  final hosts = HostRepository(store, knownHosts: knownHosts);
  runApp(PureShellApp(hosts: hosts, knownHosts: knownHosts));
}

class PureShellApp extends StatelessWidget {
  const PureShellApp({
    super.key,
    required this.hosts,
    required this.knownHosts,
  });

  final HostRepository hosts;
  final KnownHostsStore knownHosts;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PureShell',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: HostListScreen(hosts: hosts, knownHosts: knownHosts),
    );
  }
}
