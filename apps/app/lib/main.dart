import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'package:alotno/conversion.dart';
import 'package:alotno/converter_screen.dart';
import 'package:alotno/mobile/mobile_app.dart';
import 'package:alotno/src/rust/frb_generated.dart';

/// Desktop = window + menu-bar shell (macos_ui); mobile = Material share-sheet UI.
bool get _isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  // iOS / Android: a plain Material app — no window/tray (those plugins are
  // desktop-only and are never touched here).
  if (!_isDesktop) {
    runApp(const MobileApp());
    return;
  }

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(size: Size(620, 760), center: true, title: 'Alotno'),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  // Closing the window hides it; the app stays alive in the menu bar.
  // Hybrid by design: we intentionally do NOT set LSUIElement, so Alotno keeps a
  // Dock icon and behaves as a normal windowed app that also has a menu-bar item
  // (rather than a pure background/agent app). See PR #26.
  await windowManager.setPreventClose(true);

  // Menu-bar (status) item — template icon adapts to light/dark menu bars.
  await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
  await trayManager.setToolTip('Alotno — PNG to vectors');
  await trayManager.setContextMenu(
    Menu(items: [
      MenuItem(key: 'show', label: 'Open Alotno'),
      MenuItem(key: 'convert', label: 'Convert PNG to SVG…'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit Alotno'),
    ]),
  );

  runApp(const AlotnoApp());
}

class AlotnoApp extends StatefulWidget {
  const AlotnoApp({super.key});

  @override
  State<AlotnoApp> createState() => _AlotnoAppState();
}

class _AlotnoAppState extends State<AlotnoApp> with TrayListener, WindowListener {
  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _open() async {
    await windowManager.show();
    await windowManager.focus();
  }

  // Left-click the menu-bar icon → bring the converter up.
  @override
  void onTrayIconMouseDown() => _open();

  // Right-click → the menu.
  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show') {
      await _open();
    } else if (menuItem.key == 'convert') {
      await _convertQuick();
    } else if (menuItem.key == 'quit') {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  /// Menu-bar one-shot: pick a PNG, convert it to SVG (saved next to the
  /// source), and reveal the folder in Finder — all without opening the main
  /// window. Reuses the shared conversion service.
  Future<void> _convertQuick() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png'],
        allowMultiple: false,
      );
      final path = res?.files.first.path;
      if (path == null) return;
      await trayManager.setToolTip('Alotno — converting…');
      final out = await convertPngToSvgFile(path);
      await trayManager.setToolTip('Alotno — saved ${p.basename(out.path)}');
      // Reveal the output folder (sandbox-legal via NSWorkspace).
      await launchUrl(Uri.directory(p.dirname(out.path)));
    } catch (_) {
      await trayManager.setToolTip('Alotno — conversion failed');
    }
  }

  // Window close (red button) → hide instead of quit; stays in the menu bar.
  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: 'Alotno',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      home: const ConverterScreen(),
    );
  }
}
