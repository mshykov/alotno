// Widget test for the mobile (Material) converter page. Headless-safe — it's a
// plain MaterialApp/Scaffold, unlike the macOS screen's MacosWindow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alotno/mobile/mobile_app.dart';

void main() {
  testWidgets('MobileConverterPage renders and toggles formats', (tester) async {
    await tester.pumpWidget(const MobileApp());

    expect(find.text('Alotno'), findsOneWidget);
    expect(find.text('Pick a PNG to convert.'), findsOneWidget);
    expect(find.text('Convert & Share'), findsOneWidget);

    // Every format chip is present.
    for (final label in ['SVG', 'PDF', 'EPS', 'DXF', 'WEBP']) {
      expect(find.text(label), findsOneWidget);
    }

    // Toggling a chip updates state without error.
    await tester.tap(find.text('PDF'));
    await tester.pump();
    expect(find.text('PDF'), findsOneWidget);
  });
}
