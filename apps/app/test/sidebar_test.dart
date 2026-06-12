// Widget tests for the desktop sidebar + settings sheet (headless-safe: both
// only need MacosApp for theming, not a native window).

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:alotno/desktop/settings_sheet.dart';
import 'package:alotno/desktop/sidebar_content.dart';
import 'package:alotno/desktop/store.dart';

DesktopStore _storeWith({List<RecentEntry>? recents}) {
  final dir = Directory.systemTemp.createTempSync('alotno_sidebar_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  final store = DesktopStore(File('${dir.path}/s.json'));
  store.presets = DesktopStore.builtinPresets();
  store.recents = recents ?? [];
  return store;
}

void main() {
  testWidgets('SidebarContent renders presets/recents and fires callbacks', (tester) async {
    Preset? applied;
    RecentEntry? opened;
    var settingsOpened = 0;
    final store = _storeWith(recents: [
      RecentEntry(
          whenMillis: DateTime.now().millisecondsSinceEpoch - 60000,
          label: 'falcon.png',
          outDir: '/tmp/out',
          outputCount: 2,
          formats: const ['svg']),
    ]);

    await tester.pumpWidget(MacosApp(
      home: SizedBox(
        width: 240,
        child: SidebarContent(
          store: store,
          busy: false,
          onApplyPreset: (p) => applied = p,
          onDropOnPreset: (_, _) {},
          onSaveCurrentAsPreset: (_) {},
          onOpenRecent: (e) => opened = e,
          onOpenSettings: () => settingsOpened++,
        ),
      ),
    ));

    expect(find.text('Alotno'), findsOneWidget);
    expect(find.text('PRESETS'), findsOneWidget);
    expect(find.text('Logo → SVG'), findsOneWidget);
    expect(find.text('Web → WebP'), findsOneWidget);
    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text('falcon.png'), findsOneWidget);

    await tester.tap(find.text('Logo → SVG'));
    expect(applied?.name, 'Logo → SVG');

    await tester.tap(find.text('falcon.png'));
    expect(opened?.outDir, '/tmp/out');

    await tester.tap(find.text('Settings'));
    expect(settingsOpened, 1);
  });

  testWidgets('settings sheet shows default folder + clears recents', (tester) async {
    final store = _storeWith(recents: [
      RecentEntry(
          whenMillis: 0, label: 'a.png', outDir: '/x', outputCount: 1, formats: const ['svg']),
    ]);
    store.defaultOutDir = '/Users/me/Out';
    var changed = 0;

    await tester.pumpWidget(MacosApp(
      home: Builder(
        builder: (context) => PushButton(
          controlSize: ControlSize.regular,
          onPressed: () => showSettingsSheet(context, store, onChanged: () => changed++),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('/Users/me/Out'), findsOneWidget);
    expect(find.textContaining('1 recent conversion'), findsOneWidget);

    // clearRecents persists to disk — run on the real event loop (file I/O
    // never completes inside the widget test's fake-async zone).
    await tester.runAsync(() async {
      await tester.tap(find.text('Clear recents'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(store.recents, isEmpty);
    expect(changed, 1);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
  });
}
