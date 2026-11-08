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

Three commits on top of `v4.0.0` (four changes). To audit them:

    git clone https://github.com/janos-raul/xterm.dart
    cd xterm.dart
    git diff v4.0.0 1666e01c122ad7ca11c173554fda658cf3a7427b

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
3. **SGR 22 clears bold and faint.** Upstream only cleared faint ("normal
   intensity" is both), so a program that ended bold with `ESC[22m` left the text
   bold, and with bold-is-bright, bright. Faint was already cleared; bold now is
   too.
4. **Dev tooling only.** Dropped the abandoned `dart_code_metrics` dev
   dependency, which cannot be resolved on current Dart SDKs. It never affected
   packages that depend on xterm.

The behavior changes have tests in the fork
(`test/src/ui/bold_bright_test.dart`, `test/src/core/escape/sgr_intensity_test.dart`):
all 16 colors in both modes, 30-37 and 256-color forms, bold set before and
after the color, the cases that must not change, and SGR 22 for bold, faint,
both, and with bold-is-bright on.

## Known upstream behavior we did not change

- SGR 21 clears bold (as in upstream). Terminals disagree on 21: some treat it as
  bold-off, newer ones as double underline. We left it as it is. SGR 0 and
  SGR 22 also clear bold.

## Updating the pin

Change the commit in `pubspec.yaml`, run `flutter pub get`, and update the
commit in this file. Never point the dependency at a branch.
