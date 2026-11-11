# Windows desktop build: feasibility notes (experimental)

Branch `windows-build`, 2026-11-11. Exploration only, not a release.

## What the branch does

- `flutter create --platforms=windows .` added `windows/` (runner only, Android untouched).
- `lib/core/platform_support.dart`: `windowsStub` flag (uses `defaultTargetPlatform`,
  so widget tests on a Windows host still test Android behaviour).
- `lib/core/keys/software_keystore.dart`: SOFTWARE-only `KeystoreApi`. Ed25519
  software key (same path as phones without secure hardware), now only the
  fallback when Windows Hello is not set up (see windows-hello-keys.md). No TPM,
  no user prompt.
- Storage: `lib/core/storage/windows_secure_store.dart`, one DPAPI-protected JSON
  file in `%LOCALAPPDATA%\Pure-Shell\store.dat` (runner: `dpapi_channel.cpp`). The
  first builds' Roaming file (flutter_secure_storage 4.x: DPAPI JSON in
  `%APPDATA%\eu.pureshell\pureshell`) is merged in once and removed.
- App lock off on Windows (`AppLockController.supported`); Settings shows
  "Not available on Windows yet"; keep-sessions and screenshot settings hidden.
- Foreground service, notifications, FLAG_SECURE, share, app version: their Dart
  side already tolerates `MissingPluginException`, so nothing else was needed.

## Tested (real mouse/keyboard input, WSL sshd on 127.0.0.1:2222)

Works: key creation + copy of the public key, key login, host key prompt and
persistence, typing, Tab/arrows/F-keys, Ctrl+C (SIGINT), htop, live window resize
(PTY reflows; narrow window switches to portrait layout), mouse drag selection,
Ctrl+Shift+C copy, Ctrl+V and paste button, mouse-wheel scrollback, disconnect.

## Desktop phase (done, Windows only)

- Keyboard: xterm's default shortcuts are off, so every Ctrl/Alt key reaches the
  shell; Ctrl+Shift+C/V and Shift+Insert copy/paste; Alt+key = ESC + character as
  typed; AltGr characters typed as text (`lib/ui/terminal/desktop_keys.dart`).
- Text that is not a key press (IME, emoji panel, remote desktop) comes through
  `desktop_text_input.dart`: xterm's own text input client attaches without a view
  ID, which Flutter on Windows rejects, so it never received text.
- Right-click menu: Copy / Paste / Select all / Clear selection. Every paste path
  uses `sanitizePaste`, bracketed paste and the multi-line warning.
- Ctrl+= / Ctrl+- / Ctrl+0 zoom (default 14 pt), top bar always shown, extra keys
  row off (setting), dialogs max 520 px, window min 640 x 480.
- "Pure-Shell" title, framed >_ icon (`tool/make-windows-icon.py`), Windows
  wording and a Windows help, Hello-reset warning on Windows Hello keys.

Tested live against the WSL sshd: readline Ctrl+A/Ctrl+E, Alt+B, nano (Ctrl+K,
Ctrl+O, Ctrl+X), tmux prefix (Ctrl+B %, Ctrl+B d), htop, multi-line paste in bash
(bracketed, no warning) and in cat (warning), right-click copy and paste, zoom,
minimum and large window sizes, injected (VK_PACKET) text, Roaming -> Local
migration.

## Known problems

- Not tested live: a real IME (none installed), the emoji panel, AltGr layouts,
  the Hello key warning dialog (needs a Windows Hello PIN; widget-tested).
- A selection stays highlighted when a full-screen program (htop) takes over.
- Copies are normal Windows copies (they can appear in clipboard history).

## Remaining work for a release (rough, one developer: ~3-5 weeks)

| Area | Estimate |
|---|---|
| TPM keys via NCrypt / Microsoft Platform Crypto Provider (P-256, sign, list, delete, software fallback without TPM) | 3-5 days |
| Windows Hello via UserConsentVerifier | 1-2 days |
| App lock semantics for desktop (focus loss, session lock, minimise) | 2-3 days |
| ~~Desktop input/UX (shortcuts, right-click menu, zoom, IME, extra keys, title/icon/min size, wording)~~ done, see above | ~~4-6 days~~ |
| Capture exclusion, clipboard-history exclusion, version, share | 1-2 days |
| MSIX packaging, signing, Windows CI, website/README | 3-5 days + certificate |

Open design question: UserConsentVerifier is an app-level check, not bound to the
key (unlike Android's per-use key authentication). A Hello-bound key is possible via
KeyCredentialManager, but those keys are believed to be RSA-2048 only (to verify).
