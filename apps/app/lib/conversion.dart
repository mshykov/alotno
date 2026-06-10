import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:alotno/src/rust/api/simple.dart';

/// Pure conversion + file helpers shared by the converter UI
/// (`converter_screen.dart`) and the menu-bar quick-convert (`main.dart`).
///
/// No Flutter/widget dependencies — so it's unit-testable and callable outside a
/// widget context. All actual conversion lives in the Rust core via the FFI
/// bridge (`package:alotno/src/rust/api/simple.dart`).

/// Every output format the app offers, in display order. Shared by the desktop
/// and mobile UIs.
const allFormats = ['svg', 'pdf', 'eps', 'dxf', 'webp'];

/// Human-readable byte size, e.g. "1.4 MB" / "820 KB" / "512 B".
String humanSize(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// The app's standard tracing options. `preset` (low/medium/high/ultra) and
/// `colorMode` (mono/posterized) vary; the rest are fixed defaults.
TraceOptions traceOptions({String preset = 'high', String colorMode = 'mono'}) =>
    TraceOptions(
      preset: preset,
      colorMode: colorMode,
      curveType: 'curves',
      stacking: 'cutouts',
      posterizeSteps: 4,
      threshold: 128,
      version: '1.1',
      drawStyle: 'fill',
      groupBy: 'none',
      strokeColor: '#000000',
      strokeWidth: 1.0,
      nonScalingStroke: false,
      fixedSize: false,
      adobeCompat: false,
      clipOverflow: false,
    );

/// Never overwrite: atomically create `base.ext` in `dir`, falling back to
/// Finder-style " (n)" suffixes. `create(exclusive: true)` (O_EXCL) claims the
/// name atomically — no check-then-write gap a concurrent writer could slip
/// through. Async, so filesystem work stays off the UI isolate.
Future<File> createUnique(String dir, String base, String ext) async {
  for (var n = 0;; n++) {
    final name = n == 0 ? '$base.$ext' : '$base ($n).$ext';
    final file = File(p.join(dir, name));
    try {
      return await file.create(exclusive: true);
    } on FileSystemException {
      // If it now exists, it's a name collision → try the next suffix.
      // Otherwise (permission, missing dir, …) it's a real error → surface it.
      if (!await file.exists()) rethrow;
    }
  }
}

/// One-shot: a PNG file → an SVG file, saved in `outDir` (or next to the source).
/// Used by the menu-bar quick-convert. Returns the written file.
Future<File> convertPngToSvgFile(String pngPath, {String? outDir}) async {
  final bytes = await File(pngPath).readAsBytes();
  final svg = await tracePngToSvg(pngBytes: bytes, options: traceOptions());
  final dir = outDir ?? p.dirname(pngPath);
  final base = p.basenameWithoutExtension(pngPath);
  final file = await createUnique(dir, base, 'svg');
  await file.writeAsString(svg);
  return file;
}

/// Convert one PNG into every requested format, writing each into `outDir`
/// (atomically, no overwrite) and returning the written files. The mobile UI
/// passes a temp dir and hands the result to the share sheet; the same FFI
/// switch the desktop screen uses.
Future<List<File>> convertToFiles({
  required String pngPath,
  required Set<String> formats,
  required String outDir,
  TraceOptions? options,
  bool lossless = false,
}) async {
  final bytes = await File(pngPath).readAsBytes();
  final opts = options ?? traceOptions();
  final base = p.basenameWithoutExtension(pngPath);
  final out = <File>[];
  for (final fmt in formats) {
    final file = await createUnique(outDir, base, fmt);
    switch (fmt) {
      case 'svg':
        await file.writeAsString(await tracePngToSvg(pngBytes: bytes, options: opts));
      case 'eps':
        await file.writeAsString(await convertPngToEps(pngBytes: bytes, options: opts));
      case 'dxf':
        await file.writeAsString(await convertPngToDxf(pngBytes: bytes, options: opts));
      case 'pdf':
        await file.writeAsBytes(await convertPngToPdf(pngBytes: bytes, options: opts));
      default: // webp
        await file.writeAsBytes(await convertPngToWebp(
          pngBytes: bytes,
          quality: 82,
          lossless: lossless,
          mono: opts.colorMode == 'mono',
        ));
    }
    out.add(file);
  }
  return out;
}
