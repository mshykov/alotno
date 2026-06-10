import 'package:flutter/material.dart';

import 'package:alotno/design/tokens.dart';
import 'package:alotno/mobile/mobile_converter_page.dart';

/// The iOS/Android app shell. Material 3, seeded from the brand indigo so it
/// matches the web/desktop palette. (macOS keeps its macos_ui look — see
/// `AlotnoApp` in main.dart.)
class MobileApp extends StatelessWidget {
  const MobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Tokens.colorBrand500;
    return MaterialApp(
      title: 'Alotno',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const MobileConverterPage(),
    );
  }
}
