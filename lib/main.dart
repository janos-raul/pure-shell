// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import 'core/hosts/host_repository.dart';
import 'core/hosts/known_hosts.dart';
import 'core/keys/key_repository.dart';
import 'core/keys/key_service.dart';
import 'core/keys/keystore_api.dart';
import 'core/lock/app_lock_controller.dart';
import 'core/lock/app_lock_settings.dart';
import 'core/storage/screenshot_settings.dart';
import 'core/storage/secure_store.dart';
import 'core/storage/terminal_settings.dart';
import 'ui/build_guard.dart';
import 'ui/hosts/host_list_screen.dart';
import 'ui/lock/app_lock_gate.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Test-only switches must not be in a release build: refuse to start.
  final problem = buildFlagProblem(
    releaseMode: kReleaseMode,
    allowSoftwareKeystore: allowSoftwareKeystore,
    forceSoftwareKeys: forceSoftwareKeys,
  );
  if (problem != null) {
    runApp(BuildErrorApp(message: problem));
    return;
  }
  final store = FlutterSecureStore();
  final keystore = PlatformKeystore();
  // Decide whether the app starts locked before the first frame.
  final lock = AppLockController(keystore, AppLockSettings(store));
  await lock.init();
  final screenshots = ScreenshotSettings(store);
  await screenshots.init();
  final knownHosts = KnownHostsStore(store);
  final hosts = HostRepository(store, knownHosts: knownHosts);
  runApp(
    PureShellApp(
      hosts: hosts,
      knownHosts: knownHosts,
      settings: TerminalSettings(store),
      keyService: KeyService(keystore, KeyRepository(store)),
      lock: lock,
      screenshots: screenshots,
    ),
  );
}

class PureShellApp extends StatefulWidget {
  const PureShellApp({
    super.key,
    required this.hosts,
    required this.knownHosts,
    required this.settings,
    required this.keyService,
    required this.lock,
    required this.screenshots,
  });

  final HostRepository hosts;
  final KnownHostsStore knownHosts;
  final TerminalSettings settings;
  final KeyService keyService;
  final AppLockController lock;
  final ScreenshotSettings screenshots;

  @override
  State<PureShellApp> createState() => _PureShellAppState();
}

class _PureShellAppState extends State<PureShellApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PureShell',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: pureShellTheme(),
      // The lock screen sits above the navigator, so it covers dialogs too.
      builder: (context, child) => AppLockGate(
        controller: widget.lock,
        navigatorKey: _navigatorKey,
        child: child!,
      ),
      home: HostListScreen(
        hosts: widget.hosts,
        knownHosts: widget.knownHosts,
        settings: widget.settings,
        keyService: widget.keyService,
        lock: widget.lock,
        screenshots: widget.screenshots,
      ),
    );
  }
}
