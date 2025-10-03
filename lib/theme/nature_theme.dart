import 'package:flutter/material.dart';

class NaturePalette {
  // Fresh green nature palette
  static const Color primary = Color(0xFF2E7D32); // Deep green
  static const Color onPrimary = Colors.white;
  static const Color primaryContainer = Color(0xFFC8E6C9); // Light green
  static const Color onPrimaryContainer = Color(0xFF1B5E20); // Dark green

  static const Color secondary = Color(0xFF388E3C); // Medium green
  static const Color onSecondary = Colors.white;
  static const Color secondaryContainer = Color(0xFFA5D6A7); // Lighter green
  static const Color onSecondaryContainer = Color(0xFF1B5E20);

  static const Color tertiary = Color(0xFF66BB6A); // Light green accent
  static const Color onTertiary = Colors.white;

  static const Color background = Color(0xFFF1F8E9); // Very light green background
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFE8F5E9);
  static const Color onSurface = Color(0xFF1B5E20); // Dark green for text
  static const Color onSurfaceVariant = Color(0xFF2E7D32);

  static const Color outline = Color(0xFFA5D6A7);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFFFA000); // Amber
  static const Color error = Color(0xFFC62828); // Deep red
}

class NatureTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: NaturePalette.primary,
      onPrimary: NaturePalette.onPrimary,
      primaryContainer: NaturePalette.primaryContainer,
      onPrimaryContainer: NaturePalette.onPrimaryContainer,
      secondary: NaturePalette.secondary,
      onSecondary: NaturePalette.onSecondary,
      secondaryContainer: NaturePalette.secondaryContainer,
      onSecondaryContainer: NaturePalette.onSecondaryContainer,
      tertiary: NaturePalette.tertiary,
      onTertiary: NaturePalette.onTertiary,
      error: NaturePalette.error,
      onError: Colors.white,
      background: NaturePalette.background,
      onBackground: NaturePalette.onSurface,
      surface: NaturePalette.surface,
      onSurface: NaturePalette.onSurface,
      surfaceVariant: NaturePalette.surfaceVariant,
      onSurfaceVariant: NaturePalette.onSurfaceVariant,
      outline: NaturePalette.outline,
      shadow: Colors.black12,
      scrim: Colors.black26,
      inverseSurface: const Color(0xFF1B5E20),
      onInverseSurface: Colors.white,
      inversePrimary: const Color(0xFF81C784),
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
      textTheme: TextTheme(
        headlineSmall: const TextStyle(fontWeight: FontWeight.w700),
        titleLarge: const TextStyle(fontWeight: FontWeight.w700),
        titleMedium: const TextStyle(fontWeight: FontWeight.w600),
        bodyLarge: const TextStyle(fontSize: 16, color: NaturePalette.onSurface),
        bodyMedium: const TextStyle(fontSize: 14, color: NaturePalette.onSurfaceVariant),
        labelLarge: const TextStyle(fontWeight: FontWeight.w700, color: NaturePalette.onSurface),
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
      cardTheme: CardTheme(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.surfaceVariant),
        ),
        color: colorScheme.surface,
      ),
    );
  }
}

class NatureGradients {
  static LinearGradient headerGreen([double opacity = 1]) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF2E7D32).withOpacity(opacity),
        const Color(0xFF388E3C).withOpacity(opacity),
        const Color(0xFF43A047).withOpacity(opacity),
      ],
    );
  }

  static LinearGradient pillGreen() {
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        const Color(0xFF43A047),
        const Color(0xFF66BB6A),
      ],
    );
  }
}
