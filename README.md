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
- The app asks the keyboard not to learn from or store anything typed in it
  (no personalized learning, no suggestions, no autocorrect, in the terminal
  and in every text field). This is a request to the keyboard app: a
  third-party keyboard can ignore it.
- SSH keys are generated in the phone's secure hardware where the phone
  provides it (StrongBox, otherwise the TEE), are never exportable, and every
  use needs your fingerprint or screen lock. The Keys screen shows where each
  key actually lives. On a phone that reports no secure hardware, a clearly
  labelled "Software key" is used instead (Ed25519, encrypted by a Keystore
  key that also needs you for every use); it is not protected by hardware.
- The app can lock itself (fingerprint or screen lock) when opened and after a
  time away, and hides its content as soon as it loses focus. It needs a
  screen lock on the phone to do so.
- Screenshots, screen recording and the recent-apps preview are blocked by
  default (`FLAG_SECURE`); Settings has an "Allow screenshots" switch if you
  want them. Android backup and data extraction are switched off.

## Keys can be lost

Keys live in the phone's Keystore and are not backed up or exportable. They are
destroyed if you uninstall PureShell, clear its data, or reinstall it signed
with a different key (for example a build from another source). Keep another
way into your servers, such as a password or a second key. The app tells you
this once, before you create your first key.

## Status

Early development: host list, terminal, host key verification (trust on first
use, SHA-256 fingerprints), password login (asked every time, never stored),
key login with hardware-backed keys (per-use authentication) and an app lock.

Requires Android 11 (API 30) or newer.

## FAQ / troubleshooting

**SwiftKey capitalizes the first letter in the command-line box** (`echo`
becomes `Echo`). SwiftKey does this regardless of what the app asks for; the
box requests no capitalization and no autocorrect, and Gboard respects that.
Turn off "Auto-capitalization" in SwiftKey's Typing settings, or type directly
in the terminal (Direct mode), which is not affected.

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
