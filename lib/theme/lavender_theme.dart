import 'package:flutter/material.dart';

class LavenderPalette {
  static const Color primary = Color(0xFF7C4DFF);
  static const Color onPrimary = Colors.white;
  static const Color primaryContainer = Color(0xFFE6DEFF);
  static const Color onPrimaryContainer = Color(0xFF1F0066);

  static const Color secondary = Color(0xFFB388FF);
  static const Color onSecondary = Colors.black;
  static const Color secondaryContainer = Color(0xFFF1ECFF);
  static const Color onSecondaryContainer = Color(0xFF2B1B5E);

  static const Color tertiary = Color(0xFF00C853);
  static const Color onTertiary = Colors.white;

  static const Color background = Color(0xFFFBFAFF);
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFF2EEFF);
  static const Color onSurface = Color(0xFF1B1B1F);
  static const Color onSurfaceVariant = Color(0xFF4A4458);

  static const Color outline = Color(0xFFE0DAF8);
  static const Color error = Color(0xFFB00020);
}

class LavenderTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: LavenderPalette.primary,
      onPrimary: LavenderPalette.onPrimary,
      primaryContainer: LavenderPalette.primaryContainer,
      onPrimaryContainer: LavenderPalette.onPrimaryContainer,
      secondary: LavenderPalette.secondary,
      onSecondary: LavenderPalette.onSecondary,
      secondaryContainer: LavenderPalette.secondaryContainer,
      onSecondaryContainer: LavenderPalette.onSecondaryContainer,
      tertiary: LavenderPalette.tertiary,
      onTertiary: LavenderPalette.onTertiary,
      error: LavenderPalette.error,
      onError: Colors.white,
      background: LavenderPalette.background,
      onBackground: LavenderPalette.onSurface,
      surface: LavenderPalette.surface,
      onSurface: LavenderPalette.onSurface,
      surfaceVariant: LavenderPalette.surfaceVariant,
      onSurfaceVariant: LavenderPalette.onSurfaceVariant,
      outline: LavenderPalette.outline,
      shadow: Colors.black12,
      scrim: Colors.black26,
      inverseSurface: const Color(0xFF231F2A),
      onInverseSurface: Colors.white,
      inversePrimary: const Color(0xFFC7B6FF),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.background,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: colorScheme.background,
        foregroundColor: colorScheme.onSurface,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16),
        bodyMedium: TextStyle(fontSize: 14),
        labelLarge: TextStyle(fontWeight: FontWeight.w700),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surface,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outline),
    );
  }
}
