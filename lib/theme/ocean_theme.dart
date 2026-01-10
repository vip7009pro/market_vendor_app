import 'package:flutter/material.dart';

class OceanPalette {
  static const Color primary = Color(0xFF0077B6);
  static const Color onPrimary = Colors.white;
  static const Color primaryContainer = Color(0xFFCAF0F8);
  static const Color onPrimaryContainer = Color(0xFF002B45);

  static const Color secondary = Color(0xFF00B4D8);
  static const Color onSecondary = Colors.white;
  static const Color secondaryContainer = Color(0xFFBDEBFF);
  static const Color onSecondaryContainer = Color(0xFF003B4B);

  static const Color tertiary = Color(0xFF48CAE4);
  static const Color onTertiary = Colors.black;

  static const Color background = Color(0xFFF3FAFF);
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFE6F6FF);
  static const Color onSurface = Color(0xFF0E2233);
  static const Color onSurfaceVariant = Color(0xFF2E4A60);

  static const Color outline = Color(0xFFC8E6F3);
  static const Color error = Color(0xFFB00020);
}

class OceanTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: OceanPalette.primary,
      onPrimary: OceanPalette.onPrimary,
      primaryContainer: OceanPalette.primaryContainer,
      onPrimaryContainer: OceanPalette.onPrimaryContainer,
      secondary: OceanPalette.secondary,
      onSecondary: OceanPalette.onSecondary,
      secondaryContainer: OceanPalette.secondaryContainer,
      onSecondaryContainer: OceanPalette.onSecondaryContainer,
      tertiary: OceanPalette.tertiary,
      onTertiary: OceanPalette.onTertiary,
      error: OceanPalette.error,
      onError: Colors.white,
      background: OceanPalette.background,
      onBackground: OceanPalette.onSurface,
      surface: OceanPalette.surface,
      onSurface: OceanPalette.onSurface,
      surfaceVariant: OceanPalette.surfaceVariant,
      onSurfaceVariant: OceanPalette.onSurfaceVariant,
      outline: OceanPalette.outline,
      shadow: Colors.black12,
      scrim: Colors.black26,
      inverseSurface: const Color(0xFF102A3E),
      onInverseSurface: Colors.white,
      inversePrimary: const Color(0xFF8BD3FF),
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
