// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'package:flutter/foundation.dart';

/// EXPERIMENTAL (windows-build branch): the Windows desktop build has no
/// native bridges yet. Keys are software keys without a user prompt, the app
/// lock is off, and there is no foreground service, FLAG_SECURE or share
/// sheet. Everything that differs checks this flag.
///
/// defaultTargetPlatform, not dart:io Platform: widget tests report Android
/// even when run on a Windows host, so the existing tests keep testing the
/// Android behaviour.
bool get windowsStub =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
