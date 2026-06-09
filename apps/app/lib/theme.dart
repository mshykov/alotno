import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:alotno/design/tokens.dart';

/// The resolved brand palette for the current brightness, sourced from the
/// generated design tokens (`Tokens` light / `TokensDark` dark). Keeps the
/// light/dark token selection in one place instead of inline in every widget.
class AppPalette {
  const AppPalette({
    required this.accent,
    required this.sunken,
    required this.outline,
    required this.muted,
  });

  final Color accent;
  final Color sunken;
  final Color outline;
  final Color muted;

  static AppPalette of(BuildContext context) {
    final dark = MacosTheme.of(context).brightness == Brightness.dark;
    return AppPalette(
      accent: dark ? TokensDark.colorBrand500 : Tokens.colorBrand500,
      sunken: dark ? TokensDark.colorSurfaceSunken : Tokens.colorSurfaceSunken,
      outline: dark ? TokensDark.colorOutlineStrong : Tokens.colorOutlineStrong,
      muted: dark ? TokensDark.colorInkMuted : Tokens.colorInkMuted,
    );
  }
}
