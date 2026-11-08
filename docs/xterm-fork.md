# The xterm fork

PureShell draws its terminal with [xterm.dart](https://github.com/TerminalStudio/xterm.dart)
(MIT license). It uses our fork, **janos-raul/xterm.dart**, pinned in
`pubspec.yaml` to an exact commit (not a branch), so what is built is exactly
what is listed here.

- Fork: https://github.com/janos-raul/xterm.dart (branch `pureshell`)
- Based on: upstream `v4.0.0`, identical to `xterm 4.0.0` on pub.dev
- License: MIT, unchanged; copyright notices are intact
- Upstream pull request: none yet

## What the fork changes

Two commits on top of `v4.0.0` (three changes). To audit them:

    git clone https://github.com/janos-raul/xterm.dart
    cd xterm.dart
    git diff v4.0.0 626c3e26e89f609cf21c43a7fa897182976578c6

(Also in the fork: `PURESHELL_FORK.md`.)

1. **Bold is bright (optional).** New `TerminalTheme.boldIsBright`, default
   `false`. When true, bold text in one of the 8 normal ANSI colors (30-37, or
   256-color index 0-7) is drawn in the bright variant. The default foreground,
   colors 8-255, RGB colors and inverse-video cells are not changed.
   *Why:* it is the default of Windows Terminal and many terminals, so bold-blue
   directories in `ls` come out as the readable bright blue (`#3B78FF` in the
   Default theme). Upstream xterm only changes the font weight.
   PureShell turns it on in the Default (Campbell) terminal colors and leaves
   it off in Phosphor green.
2. **Palette index 15 is `brightWhite`.** Upstream returned `white`, so
   `ESC[97m` and 256-color index 15 drew the normal white.
3. **Dev tooling only.** Dropped the abandoned `dart_code_metrics` dev
   dependency, which cannot be resolved on current Dart SDKs. It never affected
   packages that depend on xterm.

Both behavior changes have tests in the fork
(`test/src/ui/bold_bright_test.dart`): every color of the 16 in both modes,
30-37 and 256-color forms, bold set before and after the color, and the cases
that must not change.

## Known upstream behavior we did not change

- SGR 22 ("normal intensity") only clears faint, not bold. A program that ends
  bold with `ESC[22m` leaves the text bold (and, with bold-is-bright, bright).
  SGR 0 and SGR 21 do clear bold.

## Updating the pin

Change the commit in `pubspec.yaml`, run `flutter pub get`, and update the
commit in this file. Never point the dependency at a branch.
