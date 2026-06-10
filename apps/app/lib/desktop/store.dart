import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A named bundle of conversion parameters, shown in the sidebar. Clicking one
/// configures the main pane; dropping PNGs onto one converts immediately.
class Preset {
  const Preset({
    required this.name,
    required this.formats,
    this.detail = 'high',
    this.colorMode = 'mono',
    this.lossless = false,
  });

  final String name;
  final Set<String> formats;
  final String detail; // low | medium | high | ultra
  final String colorMode; // mono | posterized
  final bool lossless;

  Map<String, Object?> toJson() => {
        'name': name,
        'formats': formats.toList(),
        'detail': detail,
        'colorMode': colorMode,
        'lossless': lossless,
      };

  factory Preset.fromJson(Map<String, Object?> j) => Preset(
        name: j['name'] as String,
        formats: ((j['formats'] as List?) ?? const ['svg']).cast<String>().toSet(),
        detail: (j['detail'] as String?) ?? 'high',
        colorMode: (j['colorMode'] as String?) ?? 'mono',
        lossless: (j['lossless'] as bool?) ?? false,
      );
}

/// One finished conversion, shown under RECENT. Click → reveal the output folder.
class RecentEntry {
  const RecentEntry({
    required this.whenMillis,
    required this.label,
    required this.outDir,
    required this.outputCount,
    required this.formats,
  });

  final int whenMillis; // epoch ms
  final String label; // e.g. "falcon.png" or "icons (12 files)"
  final String outDir;
  final int outputCount;
  final List<String> formats;

  DateTime get when => DateTime.fromMillisecondsSinceEpoch(whenMillis);

  Map<String, Object?> toJson() => {
        'when': whenMillis,
        'label': label,
        'outDir': outDir,
        'outputCount': outputCount,
        'formats': formats,
      };

  factory RecentEntry.fromJson(Map<String, Object?> j) => RecentEntry(
        whenMillis: (j['when'] as num).toInt(),
        label: j['label'] as String,
        outDir: j['outDir'] as String,
        outputCount: ((j['outputCount'] as num?) ?? 0).toInt(),
        formats: ((j['formats'] as List?) ?? const []).cast<String>(),
      );
}

/// Sidebar state persisted locally (presets, recents, settings). One JSON file
/// in Application Support — paths and parameters only, nothing leaves the
/// machine. Pure Dart + injectable file so it's unit-testable.
class DesktopStore {
  DesktopStore(this._file);

  final File _file;

  List<Preset> presets = [];
  List<RecentEntry> recents = [];
  String? defaultOutDir;

  static const int maxRecents = 20;

  /// Ships with opinionated starter presets; users add their own on top.
  /// Growable list (not const) — the store mutates it in add/removePreset.
  static List<Preset> builtinPresets() => [
        const Preset(name: 'Logo → SVG', formats: {'svg'}, detail: 'high', colorMode: 'mono'),
        const Preset(name: 'Web → WebP', formats: {'webp'}, detail: 'high', colorMode: 'posterized'),
        const Preset(name: 'CAD → DXF', formats: {'dxf'}, detail: 'medium', colorMode: 'mono'),
      ];

  /// Open the store at the default location (Application Support).
  static Future<DesktopStore> open() async {
    final dir = await getApplicationSupportDirectory();
    final store = DesktopStore(File(p.join(dir.path, 'alotno_state.json')));
    await store.load();
    return store;
  }

  Future<void> load() async {
    try {
      if (!await _file.exists()) {
        presets = builtinPresets();
        return;
      }
      final j = jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      presets = ((j['presets'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(Preset.fromJson)
          .toList();
      recents = ((j['recents'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(RecentEntry.fromJson)
          .toList();
      defaultOutDir = j['defaultOutDir'] as String?;
      if (presets.isEmpty) presets = builtinPresets();
    } catch (_) {
      // Corrupt/unreadable state file → start fresh rather than crash.
      presets = builtinPresets();
      recents = [];
      defaultOutDir = null;
    }
  }

  Future<void> save() async {
    final j = {
      'presets': presets.map((e) => e.toJson()).toList(),
      'recents': recents.map((e) => e.toJson()).toList(),
      'defaultOutDir': defaultOutDir,
    };
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(j));
  }

  Future<void> addRecent(RecentEntry entry) async {
    recents.insert(0, entry);
    if (recents.length > maxRecents) recents.removeRange(maxRecents, recents.length);
    await save();
  }

  Future<void> addPreset(Preset preset) async {
    // Same name replaces (lets "Save as preset" update an existing one).
    presets.removeWhere((e) => e.name == preset.name);
    presets.add(preset);
    await save();
  }

  Future<void> removePreset(String name) async {
    presets.removeWhere((e) => e.name == name);
    await save();
  }

  Future<void> clearRecents() async {
    recents = [];
    await save();
  }
}
