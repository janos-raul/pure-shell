# Pure-Shell

Pure-Shell is an open-source SSH client for Android, built with Flutter.
It connects to your servers and gets out of the way.

Website, privacy policy and terms: <https://pure-shell.eu>

## Principles

- **No cloud, no accounts, no analytics, no ads, no crash-reporting SDKs.**
  The app talks to the servers you configure and to nothing else. Its
  permissions: `INTERNET` (to reach those servers), `POST_NOTIFICATIONS` and
  `FOREGROUND_SERVICE` (to keep sessions alive in the background, with a
  notification that shows only how many are active), and `USE_BIOMETRIC`
  (the system fingerprint / screen-lock prompt, handled by Android).
- **Nothing sensitive is ever logged:** no passwords, no keys, no terminal
  content.
- **Security over convenience.** When in doubt, the app blocks and explains
  instead of warning and continuing. A changed server host key is a hard block
  with no "connect anyway" button.
- The app asks the keyboard not to learn from or store anything typed in it
  (no personalized learning anywhere; no suggestions or autocorrect in the
  terminal and the form fields; the command-line box allows suggestions and
  swipe typing, but no autocorrect). This is a request to the keyboard app: a
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
destroyed if you uninstall Pure-Shell, clear its data, or reinstall it signed
with a different key (for example a build from another source). Keep another
way into your servers, such as a password or a second key. The app tells you
this once, before you create your first key.

## Features

- Host list, terminal with extra keys (Esc, Tab, Ctrl, arrows, ...), pinch zoom.
- Host key verification: trust on first use with SHA-256 fingerprints, and a
  hard block when a key changes.
- Password login (asked every time, never stored) and key login with
  hardware-backed keys (per-use authentication).
- A command-line box (swipe typing, suggestions), copy and paste with bracketed
  paste, and a Reconnect button.
- Sessions stay alive in the background, with SSH keep-alive pings.
- An app lock, and an offline in-app Help.

Requires Android 11 (API 30) or newer.

## Getting the app

Pure-Shell will be on Google Play as a paid app: the signed, maintained build.
The source code is free software: anyone may build it from source under the
GPL (see Building).

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

Pure-Shell is free software, licensed under the GNU General Public License,
version 3 or (at your option) any later version. See [LICENSE](LICENSE).

Copyright (C) 2026 Janos-Raul
