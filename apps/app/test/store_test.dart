// Unit tests for the desktop sidebar store (presets/recents/settings JSON).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alotno/desktop/store.dart';

const _outDir = '/tmp/out';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('alotno_store_test');
    file = File('${dir.path}/state.json');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('fresh store seeds builtin presets', () async {
    final store = DesktopStore(file);
    await store.load();
    expect(store.presets.map((p) => p.name),
        containsAll(['Logo → SVG', 'Web → WebP', 'CAD → DXF']));
    expect(store.recents, isEmpty);
    expect(store.defaultOutDir, isNull);
  });

  test('round-trips presets, recents, and settings', () async {
    final store = DesktopStore(file);
    await store.load();
    await store.addPreset(const Preset(
        name: 'My fine webp',
        formats: {'webp', 'svg'},
        detail: 'ultra',
        colorMode: 'posterized',
        lossless: true));
    await store.addRecent(RecentEntry(
        whenMillis: 1700000000000,
        label: 'falcon.png',
        outDir: _outDir,
        outputCount: 2,
        formats: const ['svg', 'webp']));
    store.defaultOutDir = _outDir;
    await store.save();

    final reloaded = DesktopStore(file);
    await reloaded.load();
    final p = reloaded.presets.singleWhere((e) => e.name == 'My fine webp');
    expect(p.formats, {'webp', 'svg'});
    expect(p.detail, 'ultra');
    expect(p.lossless, isTrue);
    expect(reloaded.recents.single.label, 'falcon.png');
    expect(reloaded.recents.single.outputCount, 2);
    expect(reloaded.defaultOutDir, _outDir);
  });

  test('addPreset with same name replaces, removePreset deletes', () async {
    final store = DesktopStore(file);
    await store.load();
    await store.addPreset(const Preset(name: 'X', formats: {'svg'}));
    await store.addPreset(const Preset(name: 'X', formats: {'pdf'}));
    expect(store.presets.where((e) => e.name == 'X').single.formats, {'pdf'});
    await store.removePreset('X');
    expect(store.presets.where((e) => e.name == 'X'), isEmpty);
  });

  test('recents are capped at maxRecents, newest first', () async {
    final store = DesktopStore(file);
    await store.load();
    for (var i = 0; i < DesktopStore.maxRecents + 5; i++) {
      await store.addRecent(RecentEntry(
          whenMillis: i,
          label: 'f$i.png',
          outDir: '/tmp',
          outputCount: 1,
          formats: const ['svg']));
    }
    expect(store.recents.length, DesktopStore.maxRecents);
    expect(store.recents.first.label, 'f${DesktopStore.maxRecents + 4}.png');
  });

  test('corrupt state file recovers to defaults instead of crashing', () async {
    file.writeAsStringSync('{not valid json!!!');
    final store = DesktopStore(file);
    await store.load();
    expect(store.presets, isNotEmpty); // builtin
    expect(store.recents, isEmpty);
  });
}
