import 'package:flutter/services.dart';

/// PNGs opened *into* the app — "Open with Alotno" from the iOS Files app, or
/// Android's share sheet / open-with. The native sides
/// (`ios/Runner/AppDelegate.swift`, `android/.../MainActivity.kt`) push absolute
/// file paths over this channel; files that arrive before Dart is listening are
/// buffered natively and drained via `getInitialFiles`.
class IncomingFiles {
  static const _channel = MethodChannel('app.alotno/incoming');

  /// Start listening. Calls [onFiles] with absolute `.png` paths — once with
  /// anything that arrived before Dart was ready, then on every new arrival.
  static Future<void> init({required void Function(List<String> paths) onFiles}) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFiles') {
        final paths = (call.arguments as List).cast<String>();
        final pngs = _pngs(paths);
        if (pngs.isNotEmpty) onFiles(pngs);
      }
    });
    try {
      final initial = await _channel.invokeListMethod<String>('getInitialFiles');
      final pngs = _pngs(initial ?? const []);
      if (pngs.isNotEmpty) onFiles(pngs);
    } on MissingPluginException {
      // No native side (desktop builds, widget tests) — stream-only is fine.
    }
  }

  static List<String> _pngs(List<String> paths) =>
      paths.where((p) => p.toLowerCase().endsWith('.png')).toList();
}
