# Windows desktop build: feasibility notes (experimental)

Branch `windows-build`, 2026-11-11. Exploration only, not a release.

## What the branch does

- `flutter create --platforms=windows .` added `windows/` (runner only, Android untouched).
- `lib/core/platform_support.dart`: `windowsStub` flag (uses `defaultTargetPlatform`,
  so widget tests on a Windows host still test Android behaviour).
- `lib/core/keys/software_keystore.dart`: SOFTWARE-only `KeystoreApi`. Ed25519
  software key (same path as phones without secure hardware); the AES-GCM wrap key
  lives in flutter_secure_storage (Windows: AES-GCM files in *Roaming* %APPDATA%,
  their key in Credential Manager). No TPM, no user prompt.
- App lock off on Windows (`AppLockController.supported`); Settings shows
  "Not available on Windows yet"; keep-sessions and screenshot settings hidden.
- Foreground service, notifications, FLAG_SECURE, share, app version: their Dart
  side already tolerates `MissingPluginException`, so nothing else was needed.

## Tested (real mouse/keyboard input, WSL sshd on 127.0.0.1:2222)

Works: key creation + copy of the public key, key login, host key prompt and
persistence, typing, Tab/arrows/F-keys, Ctrl+C (SIGINT), htop, live window resize
(PTY reflows; narrow window switches to portrait layout), mouse drag selection,
Ctrl+Shift+C copy, Ctrl+V and paste button, mouse-wheel scrollback, disconnect.

## Known problems

- Ctrl+A (select all) and Ctrl+V (paste) are bound by xterm's default shortcuts on
  Windows: Ctrl+A never reaches the shell; Ctrl+V bypasses `sanitizePaste` and the
  bracketed-paste warning.
- Right-click does nothing (menu only on long press).
- Direct mode drops input that is not a real key event (emoji panel, IME, some
  remote-desktop/automation tools).
- Phone UX: small font, extra-keys row, auto-hiding bar in wide windows, full-width
  dialogs, "phone" wording, window title "pureshell", default Flutter icon.
- Data in Roaming AppData.

## Remaining work for a release (rough, one developer: ~3-5 weeks)

| Area | Estimate |
|---|---|
| TPM keys via NCrypt / Microsoft Platform Crypto Provider (P-256, sign, list, delete, software fallback without TPM) | 3-5 days |
| Windows Hello via UserConsentVerifier | 1-2 days |
| App lock semantics for desktop (focus loss, session lock, minimise) | 2-3 days |
| Desktop input/UX (shortcuts, right-click menu, zoom, IME, extra keys, title/icon/min size, wording) | 4-6 days |
| Capture exclusion, clipboard-history exclusion, version, share | 1-2 days |
| MSIX packaging, signing, Windows CI, website/README | 3-5 days + certificate |

Open design question: UserConsentVerifier is an app-level check, not bound to the
key (unlike Android's per-use key authentication). A Hello-bound key is possible via
KeyCredentialManager, but those keys are believed to be RSA-2048 only (to verify).
