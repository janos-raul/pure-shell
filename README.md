# Pure-Shell

Pure-Shell is an open-source SSH client for Android and Windows, built with
Flutter.
It connects to your servers and gets out of the way.

Website, privacy policy and terms: <https://pure-shell.eu>

What changed in each version: [CHANGELOG.md](CHANGELOG.md).

## Beta testing

Pure-Shell is in a closed test on Google Play. Testers get the app free:

1. Join the [Google Group](https://groups.google.com/g/pure-shell-testers),
   signed in with the Google account you use on your phone.
2. Open the
   [Play opt-in link](https://play.google.com/apps/testing/eu.pureshell.app)
   and tap "Become a tester".
3. We'll usually email you a free promo code after you join; if not, email
   us (the link is on <https://pure-shell.eu/#beta>). Redeem it in the Play
   Store (profile icon > Payments & subscriptions > Redeem code) before
   installing: the app is paid, so Play asks for payment otherwise.

Please keep the app installed and stay opted in for at least 14 days. Details:
<https://pure-shell.eu/#beta>. Developers: report bugs on the
[GitHub Issues](https://github.com/janos-raul/pure-shell/issues) page.

## Platforms

| Platform | Where | Requirements |
| --- | --- | --- |
| Android | Google Play | Android 11 (API 30) or newer |
| Windows | [Microsoft Store](https://apps.microsoft.com/detail/9N54CSB6MTNT) (MSIX package) | Windows 10 or 11 |

**Keys on Android:** SSH keys are ECDSA P-256 keys generated inside the
phone's Keystore, in StrongBox (a dedicated secure chip) when the phone has
one, otherwise in the TEE. The private key never leaves the hardware, and each
use needs your fingerprint or screen lock.

**Keys on Windows:** SSH keys are RSA keys held by Windows Hello. When the
computer has a TPM, the key is created in it, and the app checks this with
attestation. Each use asks for Windows Hello. Without Windows Hello the app
falls back to software keys. If Windows Hello is reset, its keys are lost.

On both platforms keys are not backed up and cannot be exported; see
[Keys can be lost](#keys-can-be-lost). Windows details:
[docs/windows-build.md](docs/windows-build.md).

## Principles

- **No cloud, no accounts, no analytics, no ads, no crash-reporting SDKs.**
  The app talks to the servers you configure and to nothing else. Its
  permissions: `INTERNET` (to reach those servers), `POST_NOTIFICATIONS`,
  `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_SPECIAL_USE` (to keep sessions
  alive in the background, with a notification that shows only how many are
  active), and `USE_BIOMETRIC` and `USE_FINGERPRINT` (the system fingerprint /
  screen-lock prompt, handled by Android; the biometric library adds
  `USE_FINGERPRINT`, its older name). AndroidX also defines one signature-level
  permission that only this app can hold,
  `eu.pureshell.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. This is the
  complete list in the built app's manifest.
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

Keys live in the phone's Keystore (on Windows, in Windows Hello) and are not
backed up or exportable. They are
destroyed if you uninstall Pure-Shell, clear its data, or reinstall it signed
with a different key (for example a build from another source). Keep another
way into your servers, such as a password or a second key. The app tells you
this once, before you create your first key.

## Features

- Host list, terminal with extra keys (Esc, Tab, Ctrl, arrows, ...), pinch zoom.
- Host key verification: trust on first use with SHA-256 fingerprints, and a
  hard block when a key changes.
- Password login (asked every time, never stored) and key login with
  hardware-backed keys (per-use authentication): the Android Keystore on
  phones, Windows Hello on Windows.
- A command-line box (swipe typing, suggestions), copy and paste with bracketed
  paste, and a Reconnect button.
- Sessions stay alive in the background, with SSH keep-alive pings.
- An app lock, and an offline in-app Help.
- On Windows: Ctrl and Alt keys go to the shell, copy and paste with
  Ctrl+Shift+C / Ctrl+Shift+V, a right-click menu, font zoom with Ctrl+= /
  Ctrl+- / Ctrl+0, and the extra-keys bar is optional.

## Getting the app

Pure-Shell is a paid app: the signed, maintained builds are on the
[Microsoft Store](https://apps.microsoft.com/detail/9N54CSB6MTNT) (Windows),
and coming to Google Play (Android), where it is in closed testing.
Terms of Service: <https://pure-shell.eu/terms/>.
The source code is free software: anyone may build it from source under the
GPL (see Building).

The only official Pure-Shell builds are on Google Play and the Microsoft Store,
published by Janos-Raul.

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
flutter build appbundle        # Play Store bundle (needs your own signing key)
```

The application ID is `eu.pureshell.app`.

### Windows (MSIX)

Requirements: the Flutter SDK with Windows desktop support, Visual Studio with
the "Desktop development with C++" workload, and PowerShell 7.

```powershell
flutter pub get
flutter test
pwsh tool/build-windows.ps1        # release build
pwsh tool/build-msix.ps1           # MSIX signed with a local test certificate
pwsh tool/build-msix.ps1 -Store    # unsigned MSIX for Microsoft Store upload
```

Always build the package through `tool/build-msix.ps1`, not a bare
`dart run msix:create`. Test certificate, install steps and packaging notes:
[docs/windows-build.md](docs/windows-build.md).

## License

Pure-Shell is free software, licensed under the GNU General Public License,
version 3 or (at your option) any later version. See [LICENSE](LICENSE).

Copyright (C) 2026 Janos-Raul

## Trademark

"Pure-Shell" and the Pure-Shell logo are not covered by the GPL. Forks and
redistributed builds must use a different name and icon.
