import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'package:alotno/converter_screen.dart';
import 'package:alotno/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await RustLib.init();

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
    } else if (menuItem.key == 'quit') {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
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
