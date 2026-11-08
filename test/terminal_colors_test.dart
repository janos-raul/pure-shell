import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/theme.dart';

void main() {
  test('Default is exactly the Campbell scheme', () {
    final t = terminalThemeFor(TerminalColors.standard);
    final got = [
      t.background,
      t.foreground,
      t.black,
      t.red,
      t.green,
      t.yellow,
      t.blue,
      t.magenta,
      t.cyan,
      t.white,
      t.brightBlack,
      t.brightRed,
      t.brightGreen,
      t.brightYellow,
      t.brightBlue,
      t.brightMagenta,
      t.brightCyan,
      t.brightWhite,
    ];
    const want = [
      0xFF0C0C0C,
      0xFFCCCCCC,
      0xFF0C0C0C,
      0xFFC50F1F,
      0xFF13A10E,
      0xFFC19C00,
      0xFF0037DA,
      0xFF881798,
      0xFF3A96DD,
      0xFFCCCCCC,
      0xFF767676,
      0xFFE74856,
      0xFF16C60C,
      0xFFF9F1A5,
      0xFF3B78FF,
      0xFFB4009E,
      0xFF61D6D6,
      0xFFF2F2F2,
    ];
    expect([for (final c in got) c.toARGB32()], want);
  });

  test('default is light gray on black, and the choice is stored', () async {
    final s = TerminalSettings(MemorySecureStore());
    expect(await s.loadColors(), TerminalColors.standard);
    expect(
      terminalThemeFor(TerminalColors.standard).foreground,
      const Color(0xFFCCCCCC),
    );
    expect(
      terminalThemeFor(TerminalColors.standard).background,
      const Color(0xFF0C0C0C),
    );
    await s.saveColors(TerminalColors.phosphor);
    expect(await s.loadColors(), TerminalColors.phosphor);
    expect(
      terminalThemeFor(TerminalColors.phosphor).foreground,
      const Color(0xFF33FF66),
    );
  });

  test('an unknown stored value falls back to the default', () async {
    final store = MemorySecureStore();
    await store.write(TerminalSettings.colorsKey, 'nonsense');
    expect(await TerminalSettings(store).loadColors(), TerminalColors.standard);
  });

  group('bold is bright (needs our xterm fork)', () {
    // The color the painter really uses for text written with [escape].
    Color textColor(TerminalTheme theme, String escape) {
      final painter = TerminalPainter(
        theme: theme,
        textStyle: const TerminalStyle(),
        textScaler: TextScaler.noScaling,
      );
      final terminal = Terminal()..write('${escape}X');
      final line = terminal.buffer.lines[0];
      return painter.resolveForegroundColor(
        line.getForeground(0),
        bold: line.getAttributes(0) & CellFlags.bold != 0,
      );
    }

    test('Default: bold blue is #3B78FF, plain blue stays #0037DA', () {
      final t = terminalThemeFor(TerminalColors.standard);
      expect(t.boldIsBright, isTrue);
      expect(textColor(t, '\x1b[1;34m'), const Color(0xFF3B78FF));
      expect(textColor(t, '\x1b[34m'), const Color(0xFF0037DA));
      // ESC[97m is the bright white, not the normal white.
      expect(textColor(t, '\x1b[97m'), const Color(0xFFF2F2F2));
    });

    test('ESC[22m (normal intensity) ends the bright color', () {
      final t = terminalThemeFor(TerminalColors.standard);
      expect(textColor(t, '\x1b[1;34m\x1b[22m'), const Color(0xFF0037DA));
    });

    test('Phosphor green leaves bold colors alone', () {
      final t = terminalThemeFor(TerminalColors.phosphor);
      expect(t.boldIsBright, isFalse);
      expect(textColor(t, '\x1b[1;34m'), t.blue);
    });
  });
}
