// Smoke test for the real Alotno converter screen.
//
// We pump `ConverterScreen` directly (not the full `AlotnoApp`, which initializes
// the window/tray managers and the Rust engine — none of which exist in a
// headless test). The screen itself builds and renders its initial state fine.
//
// SKIPPED for now: `macos_ui` leaves an internal periodic Timer running, which
// trips the test framework's pending-timer invariant at teardown. Getting this
// green needs a small harness (fake_async / a macos_ui test pump helper) — see
// the testing follow-up. The test is kept (not deleted) so it compiles under
// `flutter analyze` and documents the intended coverage.

import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:alotno/converter_screen.dart';

void main() {
  testWidgets(
    'ConverterScreen renders its initial state',
    (tester) async {
      await tester.pumpWidget(
        const MacosApp(
          debugShowCheckedModeBanner: false,
          home: ConverterScreen(),
        ),
      );
      expect(find.text('Drop PNGs to begin.'), findsOneWidget);
    },
    skip: true, // macos_ui pending-timer at teardown; needs a test harness.
  );
}
