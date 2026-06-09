// Widget tests for the extracted converter parts.
//
// We test the leaf widgets (`widgets/converter_parts.dart`) rather than the full
// `ConverterScreen`: the screen wraps `MacosWindow`, whose macos_window_utils
// visual-effect layer needs a real native window and crashes headlessly. The
// extracted parts only need a `MacosApp` (for `MacosTheme`), so they render and
// interact cleanly in CI — a concrete payoff of the widget extraction.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:alotno/widgets/converter_parts.dart';

void main() {
  testWidgets('SectionLabel renders its text uppercased', (tester) async {
    await tester.pumpWidget(
      const MacosApp(home: Center(child: SectionLabel('Output formats'))),
    );
    expect(find.text('OUTPUT FORMATS'), findsOneWidget);
  });

  testWidgets('FormatChips shows every format and reports toggles', (tester) async {
    final toggled = <String>[];
    await tester.pumpWidget(
      MacosApp(
        home: Center(
          child: FormatChips(
            selected: const {'svg'},
            busy: false,
            onToggle: toggled.add,
          ),
        ),
      ),
    );

    for (final label in ['SVG', 'PDF', 'EPS', 'DXF', 'WEBP']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('PDF'));
    expect(toggled, ['pdf']);
  });
}
