// Widget tests for the extracted converter parts.
//
// We test the leaf widgets (`widgets/converter_parts.dart`) rather than the full
// `ConverterScreen`: the screen wraps `MacosWindow`, whose macos_window_utils
// visual-effect layer needs a real native window and crashes headlessly. The
// extracted parts only need a `MacosApp` (for `MacosTheme`), so they render and
// interact cleanly in CI — a concrete payoff of the widget extraction.

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:alotno/widgets/converter_parts.dart';

// Smallest valid PNG (1×1 RGBA) for thumbnail rendering.
final Uint8List _tinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, //
  0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, //
  0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, //
  0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget _host(Widget child) => MacosApp(home: Center(child: child));

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

  testWidgets('Dropzone renders and forwards taps', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_host(SizedBox(
      width: 400,
      child: Dropzone(
        dragging: false,
        busy: false,
        onTap: () => tapped++,
        onDragEntered: () {},
        onDragExited: () {},
        onDropPaths: (_) {},
      ),
    )));
    expect(find.text('Drop PNGs here, or click to choose'), findsOneWidget);
    await tester.tap(find.byType(Dropzone));
    expect(tapped, 1);

    // Busy state swallows taps; dragging state renders the highlight branch.
    await tester.pumpWidget(_host(SizedBox(
      width: 400,
      child: Dropzone(
        dragging: true,
        busy: true,
        onTap: () => tapped++,
        onDragEntered: () {},
        onDragExited: () {},
        onDropPaths: (_) {},
      ),
    )));
    await tester.tap(find.byType(Dropzone));
    expect(tapped, 1);
  });

  testWidgets('QueueRow shows name, meta, and remove', (tester) async {
    var removed = false;
    await tester.pumpWidget(_host(SizedBox(
      width: 480,
      child: QueueRow(
        name: 'falcon.png',
        width: 64,
        height: 32,
        bytes: _tinyPng,
        busy: false,
        onRemove: () => removed = true,
      ),
    )));
    await tester.pump();
    expect(find.text('falcon.png'), findsOneWidget);
    expect(find.textContaining('64×32'), findsOneWidget);
    await tester.tap(find.byType(MacosIconButton));
    expect(removed, isTrue);
  });

  testWidgets('OptionsPanel renders pickers and toggles lossless', (tester) async {
    bool? lossless;
    await tester.pumpWidget(_host(SizedBox(
      width: 560,
      child: OptionsPanel(
        preset: 'high',
        colorMode: 'mono',
        showLossless: true,
        lossless: false,
        busy: false,
        onPreset: (_) {},
        onColorMode: (_) {},
        onLossless: (v) => lossless = v,
      ),
    )));
    expect(find.text('Detail  '), findsOneWidget);
    expect(find.text('Color  '), findsOneWidget);
    expect(find.text('Lossless WebP'), findsOneWidget);
    await tester.tap(find.byType(MacosCheckbox));
    expect(lossless, isTrue);

    // Without webp selected the lossless row is absent.
    await tester.pumpWidget(_host(SizedBox(
      width: 560,
      child: OptionsPanel(
        preset: 'low',
        colorMode: 'posterized',
        showLossless: false,
        lossless: false,
        busy: false,
        onPreset: (_) {},
        onColorMode: (_) {},
        onLossless: (_) {},
      ),
    )));
    expect(find.text('Lossless WebP'), findsNothing);
  });

  testWidgets('OutputRow shows placeholder or path and fires choose', (tester) async {
    var chose = 0;
    await tester.pumpWidget(_host(SizedBox(
      width: 480,
      child: OutputRow(outDir: null, busy: false, onChoose: () => chose++),
    )));
    expect(find.text('No folder chosen'), findsOneWidget);
    await tester.tap(find.text('Choose…'));
    expect(chose, 1);

    await tester.pumpWidget(_host(SizedBox(
      width: 480,
      child: OutputRow(outDir: '/tmp/out', busy: false, onChoose: () {}),
    )));
    expect(find.text('/tmp/out'), findsOneWidget);
  });

  testWidgets('ActionsBar states: idle, busy, reveal', (tester) async {
    var converted = 0;
    var revealed = 0;
    await tester.pumpWidget(_host(SizedBox(
      width: 560,
      child: ActionsBar(
        canConvert: true,
        busy: false,
        queueCount: 3,
        showReveal: true,
        status: 'Ready.',
        onConvert: () => converted++,
        onReveal: () => revealed++,
      ),
    )));
    expect(find.text('Convert 3 files'), findsOneWidget);
    expect(find.text('Ready.'), findsOneWidget);
    await tester.tap(find.text('Convert 3 files'));
    await tester.tap(find.text('Reveal in Finder'));
    expect(converted, 1);
    expect(revealed, 1);

    await tester.pumpWidget(_host(SizedBox(
      width: 560,
      child: ActionsBar(
        canConvert: false,
        busy: true,
        queueCount: 1,
        showReveal: false,
        status: 'Converting…',
        onConvert: () {},
        onReveal: () {},
      ),
    )));
    // Busy branch: progress + label, no reveal button.
    expect(find.text('Converting…'), findsNWidgets(2)); // button label + status
    expect(find.text('Reveal in Finder'), findsNothing);
  });
}