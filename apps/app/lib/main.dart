import 'package:flutter/material.dart';

import 'src/rust/api/simple.dart';
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
    // Brand indigo from DESIGN.md / design tokens (#6366F1).
    const indigo = Color(0xFF6366F1);
    return MaterialApp(
      title: 'Alotno',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: indigo, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Alotno')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Alotno',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('PNG → SVG · PDF · EPS · DXF · WebP'),
              const SizedBox(height: 24),
              // Synchronous Dart→Rust→alotno-core call — proves the bridge works.
              Text(engineInfo(), style: const TextStyle(color: indigo)),
            ],
          ),
        ),
      ),
    );
  }
}
