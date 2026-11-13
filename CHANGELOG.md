# Changelog

All notable changes to Pure-Shell. Versions are the app version
(`x.y.z`). Android builds also carry a build number (`+N`); Windows packages
are `x.y.z.0`.

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
