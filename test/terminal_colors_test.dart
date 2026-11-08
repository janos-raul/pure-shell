import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/storage/secure_store.dart';
import 'package:pureshell/core/storage/terminal_settings.dart';
import 'package:pureshell/ui/theme.dart';

void main() {
  test('default is light gray on black, and the choice is stored', () async {
    final s = TerminalSettings(MemorySecureStore());
    expect(await s.loadColors(), TerminalColors.standard);
    expect(
      terminalThemeFor(TerminalColors.standard).foreground,
      const Color(0xFFCCCCCC),
    );
    expect(
      terminalThemeFor(TerminalColors.standard).background,
      const Color(0xFF000000),
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
}
