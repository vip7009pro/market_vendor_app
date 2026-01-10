import 'package:flutter/material.dart';

class MidnightPalette {
  static const Color primary = Color(0xFF00E5FF);
  static const Color onPrimary = Colors.black;
  static const Color primaryContainer = Color(0xFF003A44);
  static const Color onPrimaryContainer = Color(0xFFA7F6FF);

  static const Color secondary = Color(0xFFFFD54F);
  static const Color onSecondary = Colors.black;
  static const Color secondaryContainer = Color(0xFF3A2E00);
  static const Color onSecondaryContainer = Color(0xFFFFE9A8);

  static const Color tertiary = Color(0xFFFF4081);
  static const Color onTertiary = Colors.white;

  static const Color background = Color(0xFF0B1220);
  static const Color surface = Color(0xFF111A2E);
  static const Color surfaceVariant = Color(0xFF17213A);
  static const Color onSurface = Color(0xFFE6EAF2);
  static const Color onSurfaceVariant = Color(0xFFB7C0D6);

  static const Color outline = Color(0xFF2A3553);
  static const Color error = Color(0xFFFFB4AB);
}

class MidnightTheme {
  static ThemeData dark() {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: MidnightPalette.primary,
      onPrimary: MidnightPalette.onPrimary,
      primaryContainer: MidnightPalette.primaryContainer,
      onPrimaryContainer: MidnightPalette.onPrimaryContainer,
      secondary: MidnightPalette.secondary,
      onSecondary: MidnightPalette.onSecondary,
      secondaryContainer: MidnightPalette.secondaryContainer,
      onSecondaryContainer: MidnightPalette.onSecondaryContainer,
      tertiary: MidnightPalette.tertiary,
      onTertiary: MidnightPalette.onTertiary,
      error: MidnightPalette.error,
      onError: Colors.black,
      background: MidnightPalette.background,
      onBackground: MidnightPalette.onSurface,
      surface: MidnightPalette.surface,
      onSurface: MidnightPalette.onSurface,
      surfaceVariant: MidnightPalette.surfaceVariant,
      onSurfaceVariant: MidnightPalette.onSurfaceVariant,
      outline: MidnightPalette.outline,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: const Color(0xFFE6EAF2),
      onInverseSurface: const Color(0xFF0B1220),
      inversePrimary: const Color(0xFF00B8CC),
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
