// Pure unit tests for the conversion service (no widgets, no FFI native calls,
// no timers) — so they run reliably under `flutter test` in CI.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:alotno/conversion.dart';

void main() {
  group('humanSize', () {
    test('formats bytes / KB / MB', () {
      expect(humanSize(512), '512 B');
      expect(humanSize(2048), '2 KB');
      expect(humanSize(1572864), '1.5 MB');
      expect(humanSize(0), '0 B');
    });
  });

  group('traceOptions', () {
    test('defaults', () {
      final o = traceOptions();
      expect(o.preset, 'high');
      expect(o.colorMode, 'mono');
      expect(o.threshold, 128);
      expect(o.curveType, 'curves');
      expect(o.strokeColor, '#000000');
    });

    test('overrides preset + colorMode', () {
      final o = traceOptions(preset: 'low', colorMode: 'posterized');
      expect(o.preset, 'low');
      expect(o.colorMode, 'posterized');
    });
  });

  group('createUnique', () {
    test('never overwrites — appends Finder-style suffixes', () async {
      final dir = await Directory.systemTemp.createTemp('alotno_unique_test');
      try {
        final f1 = await createUnique(dir.path, 'icon', 'svg');
        expect(p.basename(f1.path), 'icon.svg');
        expect(await f1.exists(), isTrue);

        final f2 = await createUnique(dir.path, 'icon', 'svg');
        expect(p.basename(f2.path), 'icon (1).svg');

        final f3 = await createUnique(dir.path, 'icon', 'svg');
        expect(p.basename(f3.path), 'icon (2).svg');

        // Distinct files all exist (nothing was overwritten).
        expect(await f1.exists(), isTrue);
        expect(await f2.exists(), isTrue);
        expect(await f3.exists(), isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
