# Changelog

All notable changes to Pure-Shell. Versions are the app version
(`x.y.z`). Android builds also carry a build number (`+N`); Windows packages
are `x.y.z.0`.

## 1.3.0 (unreleased; Android and Windows)

### Added

- **Snippets (saved commands).** Save a command, or several lines, once and
  use it on any session. Each snippet has a name, the text, a scope (every host
  or one host) and a mode: **Insert** puts it in the command box to edit,
  **Run** sends it followed by Enter. Several lines are sent as one paste
  (bracketed when the program asked for it). A run snippet can ask before it
  runs; that is on by default for several lines. Open the list with the new
  Snippets key in the extra keys row, the icon in the top bar (in landscape:
  tap the top edge of the screen first) or, on Windows, **Ctrl+Shift+S**.
  The host's own snippets come first, then the ones for every host. Manage
  them (add, edit, delete, reorder) from the list, from the Snippets entry in
  the host list menu, or from a host's settings. Snippets are stored encrypted
  like hosts and are deleted with their host. The editor reminds you not to
  put passwords or secrets in them. There is a Help topic "Snippets".
- **Windows: Help topic "Try the test server (Sandbox)".** Windows 1.2.0.0
  shipped without it; the Android topic came with 1.2.0. Same steps and the
  same fingerprint to compare, with Windows Hello wording for the key.

### Changed

- **Windows: no more "experimental" wording.** The About screen now says
  "An open-source SSH client." on both platforms, and the software-key notices
  and Help no longer call the Windows build experimental (what they say about
  the key is unchanged).
- **Internal: moved to `package:material_ui`.** Flutter 3.50 deprecates
  `package:flutter/material.dart`. No visible change.
- **SSH library updated to dartssh2 4.2.0.** Fixes the connection closing when
  a server asks to change an expired password (the app now moves on to the next
  login method), and ignores credential results that arrive after an attempt
  has already ended.
- **Clean logout.** When you end a session (close the tab, disconnect, leave
  the app), Pure-Shell now sends the server an SSH disconnect message first, so
  the server's log shows a normal logout instead of a lost connection. Failed
  connections and dead links are still closed without it. Nothing changes on
  screen.

## 1.2.0 (2026-11-21)

### Added

- **Help: "Try the test server (Sandbox)".** A free throwaway Linux server to
  try Pure-Shell without a server of your own. The topic explains
  how to connect (create a key named Sandbox, add the host), shows the
  server's host key fingerprint to compare on the first connection (copyable),
  and says what to do if the key is rejected (one session per network).
  Sessions on the Sandbox are recorded and kept up to 14 days, and end after
  30 minutes: see <https://pure-shell.eu/sandbox/> and the
  [privacy policy](https://pure-shell.eu/privacy.html#test-servers). The app
  itself still connects only to servers you add yourself.
- **Chat (website and server only, not in the app).** A public text chat
  room over SSH for Pure-Shell users and testers (ssh-chat), reachable with any
  SSH client at `chat.pure-shell.eu`, port 2022. How to join and the rules:
  <https://pure-shell.eu/chat/>. The chat server does not log messages; see the
  [privacy policy](https://pure-shell.eu/privacy.html#test-servers).

### Changed

- **Terms of Service and Privacy Policy updated** (2026-11-21) for the test
  servers (Sandbox and Chat): who may use them (18 or older), what is
  recorded and for how long (Sandbox sessions up to 14 days; the Chat server
  keeps no messages), and the rules of use. Read them at
  <https://pure-shell.eu/terms/> and <https://pure-shell.eu/privacy.html>.
- Updated the Android build tools (Gradle, Android Gradle Plugin, Kotlin) and
  the libraries the app builds on.

## 1.1.2 (2026-11-13)

### Changed

- **Terms of Service updated** (effective 2026-11-13) for Windows and the
  Microsoft Store: purchases and refunds through the store you bought from
  (Google Play or the Microsoft Store), when keys are lost on Windows, and
  Windows 10 or 11 as a requirement. Read them at
  <https://pure-shell.eu/terms/>.

### Fixed

- The server could be told a taller terminal than the one on screen. The
  shell is opened with the size of the first frame; if the view changed while
  it opened (on Windows, the extra-keys bar appearing), that change was lost.
  Full-screen and progress output then went wrong: apt's progress bar, for
  example, scrolled up with the text on every update instead of staying on the
  last line. The terminal size is now sent again once the shell is open.
  Android and Windows.

## 1.1.1 (2026-11-10; Windows 2026-11-12)

### Added

- **Windows.** First Windows release, as an MSIX package for the Microsoft
  Store (Windows 10 or 11):
  - SSH keys held by Windows Hello, in the computer's TPM where it has one
    (checked with attestation); Windows Hello is asked on every use. Without
    Windows Hello the app offers a software Ed25519 key.
  - Hosts and settings stored in the app's local storage, encrypted with the
    Windows Data Protection API for your Windows user.
  - Desktop keys: Ctrl and Alt combinations go to the shell; copy and paste
    with Ctrl+Shift+C / Ctrl+Shift+V; a right-click menu in the terminal;
    font zoom with Ctrl+= / Ctrl+- / Ctrl+0.
  - The extra-keys bar is optional on the desktop.
  - App lock with Windows Hello: on Windows session lock and after a long
    minimise. Not over Remote Desktop, where Windows Hello is not available;
    the lock applies again back at the computer.
  - "Allow screenshots" off blocks screen capture of the window; copied
    terminal text is kept out of the clipboard history and the cloud
    clipboard.
  - The app version is shown in About.

### Fixed

- Android: the Create key dialog overflowed above the keyboard on small
  screens; it now scrolls.

## 1.1.0 (2026-11-10)

### Changed

- The app is named Pure-Shell, with a new icon: the framed `>_` prompt.
- Console look: grey text with green accents, blue headings and emphasis,
  amber key icons, and settings grouped in boxes.
- New keys get the comment `pure-shell` by default.
- The password fallback switch says what it does: if the server rejects the
  key, you are asked before a password is used. Off by default.

### Added

- A help topic on StrongBox, TEE and software keys.

## 1.0.0 (2026-11-09)

First version, for Android 11 or newer.

- Host list with a key or password icon per host, and a welcome screen on
  first run.
- Host key verification: trust on first use with SHA-256 fingerprints, and a
  hard block, with no "connect anyway", when a server's key changes.
- Password login, asked every time and never stored.
- Key login with ECDSA P-256 keys generated in the phone's Keystore
  (StrongBox, otherwise the TEE), never exportable, with fingerprint or screen
  lock on every use. Phones without secure hardware get a clearly labelled
  software Ed25519 key. The Keys screen shows where each key lives, and a
  notice before the first key explains that keys cannot be backed up.
- Terminal with extra keys (Esc, Tab, Ctrl, arrows, ...), pinch zoom, Direct
  key-by-key input, and a command-line box above the keyboard.
- Copy and paste (bracketed paste), and a Reconnect button when a session
  ends.
- Terminal colors: Default (the Windows Terminal Campbell scheme, with bold
  text in a normal color drawn bright) and Phosphor green.
- Sessions stay alive in the background (a notification shows only how many
  are active), with SSH keep-alive that notices a dead connection.
- App lock with fingerprint or screen lock; content hidden when the app loses
  focus.
- Privacy: the keyboard is asked not to learn from what you type;
  screenshots, screen recording and the recent-apps preview are blocked by
  default ("Allow screenshots" in Settings); Android backup is off.
- Offline in-app Help and an About screen.
