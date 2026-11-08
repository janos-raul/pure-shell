# PureShell

PureShell is an open-source SSH client for Android, built with Flutter.
It connects to your servers and gets out of the way.

## Principles

- **No cloud, no accounts, no analytics, no ads, no crash-reporting SDKs.**
  The app talks to the servers you configure and to nothing else. Its only
  permission is `INTERNET`.
- **Nothing sensitive is ever logged:** no passwords, no keys, no terminal
  content.
- **Security over convenience.** When in doubt, the app blocks and explains
  instead of warning and continuing. A changed server host key is a hard block
  with no "connect anyway" button.
- Screenshots and the recent-apps preview are disabled (`FLAG_SECURE`), and
  Android backup and data extraction are switched off.

## Status

Early development (phase 1): host list, password login, terminal, and host key
verification (trust on first use, SHA-256 fingerprints). Passwords are asked
for on every connection and are never stored.

Requires Android 9 (API 28) or newer.

## Building

Requirements: the Flutter SDK (stable channel) and the Android SDK.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug      # or: flutter run
```

The application ID is `eu.pureshell.app`.

## License

PureShell is free software, licensed under the GNU General Public License,
version 3 or (at your option) any later version. See [LICENSE](LICENSE).

Copyright (C) 2026 Janos-Raul
