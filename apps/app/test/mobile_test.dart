// Widget tests for the mobile (Material) converter page. Headless-safe — it's a
// plain MaterialApp/Scaffold, unlike the macOS screen's MacosWindow.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alotno/mobile/mobile_app.dart';

// Smallest valid PNG (1×1 RGBA) — same bytes the core tests use. The queue
// renders previews via Image.memory, so injected files must be real PNGs.
const _tinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, //
  0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, //
  0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, //
  0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// Simulate the native side pushing opened/shared files over the
/// `app.alotno/incoming` channel (what AppDelegate/MainActivity do).
Future<void> _injectIncoming(WidgetTester tester, List<String> paths) async {
  const codec = StandardMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'app.alotno/incoming',
    codec.encodeMethodCall(MethodCall('openFiles', paths)),
    (_) {},
  );
}

void main() {
  testWidgets('MobileConverterPage renders and toggles formats', (tester) async {
    await tester.pumpWidget(const MobileApp());

    expect(find.text('Alotno'), findsOneWidget);
    expect(find.text('Pick PNGs to convert.'), findsOneWidget);
    expect(find.text('Convert & Share'), findsOneWidget);

    for (final label in ['SVG', 'PDF', 'EPS', 'DXF', 'WEBP']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('PDF'));
    await tester.pump();
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets('incoming shared PNGs land in the queue and can be removed', (tester) async {
    // Sync I/O only: async dart:io futures never complete inside the widget
    // test's fake-async zone (they'd hang the test).
    final dir = Directory.systemTemp.createTempSync('alotno_incoming_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final a = File('${dir.path}/falcon.png')..writeAsBytesSync(_tinyPng);
    final b = File('${dir.path}/wing.png')..writeAsBytesSync(_tinyPng);
    final notPng = File('${dir.path}/notes.txt')..writeAsStringSync('not a png');

    await tester.pumpWidget(const MobileApp());

    // Native pushes three paths; only the two PNGs should be queued. The page
    // reads the files with real dart:io, so run the injection in runAsync
    // (real event loop) instead of the widget test's fake-async zone.
    await tester.runAsync(() async {
      await _injectIncoming(tester, [a.path, b.path, notPng.path]);
      // Let the page's real file reads complete before pumping.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('falcon.png'), findsOneWidget);
    expect(find.text('wing.png'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
    // Multi-file convert button label proves both files are queued. (The status
    // line is below the fold of the test viewport — not asserted.)
    expect(find.text('Convert & Share 2 files'), findsOneWidget);

    // Remove one from the queue.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    expect(find.text('falcon.png'), findsNothing);
    expect(find.text('wing.png'), findsOneWidget);
  });
}
