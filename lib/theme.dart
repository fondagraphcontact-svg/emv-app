import 'package:flutter/material.dart';

class EmvColors {
  static const accent = Color(0xFFFF8A00);
  // Palette "bleu d'architecte" (cyanotype) : fond bleu profond, traits blancs.
  static const background = Color(0xFF0B2E5C);
  static const surface = Color(0xFF113A70);
  static const surfaceHigh = Color(0xFF17478A);
  static const partStroke = Color(0xFFF4F8FF);
  static const partFill = Color(0xFF2A5A9C);
  static const guide = Color(0xFF9DB9E8);
  static const label = Color(0xFFE6EEFB);
  static const grid = Color(0xFF3B6DB3);

  static Color severity(int s) => switch (s) {
        >= 3 => const Color(0xFFE5484D),
        2 => accent,
        _ => const Color(0xFF4CC38A),
      };
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: EmvColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: EmvColors.accent,
    onPrimary: Colors.black,
    secondary: EmvColors.accent,
    surface: EmvColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: EmvColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: EmvColors.background,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: EmvColors.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: EmvColors.surface,
      indicatorColor: EmvColors.accent.withValues(alpha: 0.25),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? EmvColors.accent
              : Colors.white70)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: EmvColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: EmvColors.surface,
      showDragHandle: true,
    ),
    dividerColor: Colors.white12,
  );
}
