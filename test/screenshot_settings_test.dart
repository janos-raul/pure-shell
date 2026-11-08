import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/storage/screenshot_settings.dart';
import 'package:pureshell/core/storage/secure_store.dart';

class _FakeWindow implements WindowSecurity {
  final calls = <bool>[];
  @override
  Future<void> setSecure(bool secure) async => calls.add(secure);
}

void main() {
  test('secure by default', () async {
    final w = _FakeWindow();
    final s = ScreenshotSettings(MemorySecureStore(), w);
    await s.init();
    expect(s.allowed, isFalse);
    expect(w.calls, [true]);
  });

  test('allowing lifts the flag and survives a restart', () async {
    final store = MemorySecureStore();
    final w = _FakeWindow();
    final s = ScreenshotSettings(store, w);
    await s.init();
    await s.setAllowed(true);
    expect(w.calls.last, isFalse);

    final w2 = _FakeWindow();
    final again = ScreenshotSettings(store, w2);
    await again.init();
    expect(again.allowed, isTrue);
    expect(w2.calls, [false]);

    await again.setAllowed(false);
    expect(w2.calls.last, isTrue);
  });
}
