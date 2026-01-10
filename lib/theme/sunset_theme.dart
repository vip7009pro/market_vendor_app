import 'package:flutter/material.dart';

class SunsetPalette {
  static const Color primary = Color(0xFFFF6D00);
  static const Color onPrimary = Colors.white;
  static const Color primaryContainer = Color(0xFFFFE0B2);
  static const Color onPrimaryContainer = Color(0xFF4E2600);

  static const Color secondary = Color(0xFFFF1744);
  static const Color onSecondary = Colors.white;
  static const Color secondaryContainer = Color(0xFFFFDADF);
  static const Color onSecondaryContainer = Color(0xFF5C0013);

  static const Color tertiary = Color(0xFFFFC107);
  static const Color onTertiary = Colors.black;

  static const Color background = Color(0xFFFFFBF5);
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFFFF0E0);
  static const Color onSurface = Color(0xFF2A1B14);
  static const Color onSurfaceVariant = Color(0xFF5A3C2E);

  static const Color outline = Color(0xFFF3D5C3);
  static const Color error = Color(0xFFB00020);
}

class SunsetTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: SunsetPalette.primary,
      onPrimary: SunsetPalette.onPrimary,
      primaryContainer: SunsetPalette.primaryContainer,
      onPrimaryContainer: SunsetPalette.onPrimaryContainer,
      secondary: SunsetPalette.secondary,
      onSecondary: SunsetPalette.onSecondary,
      secondaryContainer: SunsetPalette.secondaryContainer,
      onSecondaryContainer: SunsetPalette.onSecondaryContainer,
      tertiary: SunsetPalette.tertiary,
      onTertiary: SunsetPalette.onTertiary,
      error: SunsetPalette.error,
      onError: Colors.white,
      background: SunsetPalette.background,
      onBackground: SunsetPalette.onSurface,
      surface: SunsetPalette.surface,
      onSurface: SunsetPalette.onSurface,
      surfaceVariant: SunsetPalette.surfaceVariant,
      onSurfaceVariant: SunsetPalette.onSurfaceVariant,
      outline: SunsetPalette.outline,
      shadow: Colors.black12,
      scrim: Colors.black26,
      inverseSurface: const Color(0xFF2B1A12),
      onInverseSurface: Colors.white,
      inversePrimary: const Color(0xFFFFB170),
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
