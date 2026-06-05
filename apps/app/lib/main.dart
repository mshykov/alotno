import 'package:flutter/material.dart';

import 'converter_screen.dart';
import 'design/tokens.dart';
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
    return MaterialApp(
      title: 'Alotno',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Tokens.colorBrand500, useMaterial3: true),
      home: const ConverterScreen(),
    );
  }
}
