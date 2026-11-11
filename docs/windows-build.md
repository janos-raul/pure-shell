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

## Lock and protection phase (done, Windows only)

- App lock: locks on Windows session lock (Win+L, sleep) and on a Remote Desktop
  disconnect, and when the window has been minimised longer than the timeout; never
  on focus changes (alt-tab). Windows Hello unlocks it (UserConsentVerifier,
  window-aware interop call), prompted only while the window is visible. Without
  Hello the lock is unavailable and Settings says why. Key presses no longer reach
  the server while locked.
- Remote Desktop (decision): Hello user verification is not available over RDP, so
  the lock does not apply there; a lock from the computer is lifted when connecting
  over RDP. After a session lock or RDP disconnect, signing in at the computer
  again locks the app.
- Capture blocking: SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE, fallback
  WDA_MONITOR) for the "Allow screenshots" setting, blocked from window creation.
- Clipboard: terminal copies carry ExcludeClipboardContentFromMonitorProcessing,
  CanIncludeInClipboardHistory = 0 and CanUploadToCloudClipboard = 0.
- The selection is cleared when a program switches to/from the alternate screen.

Verified live (over Remote Desktop): capture blocking (window absent from screen
capture, PrintWindow black), Hello unavailable over RDP (lock off, no prompt).
Assumed, not tested live yet (needs the physical machine): PIN at start, Win+L,
minimise past the timeout, alt-tab, Win+V history exclusion (clipboard history is
off on the test machine), htop selection clear (widget-tested).

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

## MSIX package (local test installs)

Build: `pwsh tool/build-msix.ps1` -> `debug\msix\Pure-Shell.msix`, signed with a
local TEST certificate. `pwsh tool/build-msix.ps1 -Store` builds the unsigned
Store variant (`--store`; Partner Center signs it).

`msix_config` in pubspec.yaml: `identity_name` (`PureShell.Test`) and `publisher`
(`CN=Pure-Shell Test`) are PLACEHOLDERS and must be replaced with the Partner
Center values before any Store submission. `msix_version` is the app version with
a 4th part 0. Capabilities: `internetClient`, `privateNetworkClientServer` (SSH to
LAN hosts); the Flutter runner is a full-trust desktop app (`runFullTrust`).

The test certificate is created on the first build in `windows\packaging\`
(gitignored, never commit): `test-cert.pfx` (private key), `test-cert.password`,
`test-cert.cer` (public part). Its subject must equal `publisher`.

Trust it once (elevated PowerShell), so Windows accepts the package:

    Import-Certificate -FilePath windows\packaging\test-cert.cer `
        -CertStoreLocation Cert:\LocalMachine\TrustedPeople

Install / update / uninstall (normal PowerShell):

    Add-AppxPackage debug\msix\Pure-Shell.msix
    Get-AppxPackage PureShell.Test            # PackageFamilyName, install path
    Remove-AppxPackage (Get-AppxPackage PureShell.Test).PackageFullName

Remove the trust again (elevated):

    Get-ChildItem Cert:\LocalMachine\TrustedPeople |
        Where-Object Subject -eq 'CN=Pure-Shell Test' | Remove-Item
Install on another PC: `tool/build-msix.ps1` also writes `debug\msix\install\`
(Pure-Shell.msix, test-cert.cer, install.ps1). Copy that folder and run
`powershell -ExecutionPolicy Bypass -File install.ps1` (asks for admin once to trust
the certificate; reinstalls when the same version is installed, since Windows
refuses a same-version update with different content). `install.ps1 -Uninstall`
removes it.

Packaged vs unpackaged (tested 2026-11-11, Windows 11 26300):
- Storage: packaged desktop apps get AppData virtualisation. On a clean PC the
  store lands in `%LOCALAPPDATA%\Packages\PureShell.Test_meab6r7t5qkq0\LocalCache\
  Local\Pure-Shell\store.dat` and is removed on uninstall. If
  `%LOCALAPPDATA%\Pure-Shell` already exists (a dev build ran), the package reads
  and writes that real folder instead (shared with the dev build; survives
  uninstall). Deletes reach the real Roaming folder, so the one-time Roaming
  migration behaves as in the dev build.
- Start menu entry "Pure-Shell" with the framed >_ logo; About shows the version.
Tested on a second PC (clean install from `debug\msix\install`, local session, by
the user, 2026-11-11): Windows Hello key created in the package with TPM
attestation ("TPM + Hello"), SSH login to a LAN server with it (PIN on every
login), and the remaining checks (app lock, capture blocking, clipboard history,
key deletion) reported fine.