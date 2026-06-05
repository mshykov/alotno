import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';

import 'converter_screen.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const AlotnoApp());
}

class AlotnoApp extends StatelessWidget {
  const AlotnoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: 'Alotno',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system, // respect macOS appearance (light/dark)
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      home: const ConverterScreen(),
    );
  }
}
