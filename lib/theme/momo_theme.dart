import 'package:flutter/material.dart';

class MomoPalette {
  // Core brand colors (approximate MoMo palette)
  static const Color primary = Color(0xFFD82D8B); // strong pink
  static const Color onPrimary = Colors.white;
  static const Color primaryContainer = Color(0xFFF8D3E8);
  static const Color onPrimaryContainer = Color(0xFF5B0C3A);

  static const Color secondary = Color(0xFFFF4DA6);
  static const Color onSecondary = Colors.white;
  static const Color secondaryContainer = Color(0xFFFFD1E8);
  static const Color onSecondaryContainer = Color(0xFF5C1138);

  static const Color tertiary = Color(0xFF00C2FF); // accent cyan used in icons
  static const Color onTertiary = Colors.white;

  static const Color background = Color(0xFFFDF7FB); // soft pinkish background
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFF2E7F1);
  static const Color onSurface = Color(0xFF1E1E1E);
  static const Color onSurfaceVariant = Color(0xFF505050);

  static const Color outline = Color(0xFFE7D7E2);
  static const Color success = Color(0xFF1EB980);
  static const Color warning = Color(0xFFFFB020);
  static const Color error = Color(0xFFB00020);
}

class MomoTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: MomoPalette.primary,
      onPrimary: MomoPalette.onPrimary,
      primaryContainer: MomoPalette.primaryContainer,
      onPrimaryContainer: MomoPalette.onPrimaryContainer,
      secondary: MomoPalette.secondary,
      onSecondary: MomoPalette.onSecondary,
      secondaryContainer: MomoPalette.secondaryContainer,
      onSecondaryContainer: MomoPalette.onSecondaryContainer,
      tertiary: MomoPalette.tertiary,
      onTertiary: MomoPalette.onTertiary,
      error: MomoPalette.error,
      onError: Colors.white,
      background: MomoPalette.background,
      onBackground: MomoPalette.onSurface,
      surface: MomoPalette.surface,
      onSurface: MomoPalette.onSurface,
      surfaceVariant: MomoPalette.surfaceVariant,
      onSurfaceVariant: MomoPalette.onSurfaceVariant,
      outline: MomoPalette.outline,
      shadow: Colors.black12,
      scrim: Colors.black26,
      inverseSurface: const Color(0xFF2A2730),
      onInverseSurface: Colors.white,
      inversePrimary: const Color(0xFF9C1F67),
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
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: MomoPalette.onSurface,
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
          side: BorderSide(color: colorScheme.primary, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          foregroundColor: colorScheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.primaryContainer,
        selectedColor: colorScheme.primary,
        labelStyle: TextStyle(color: colorScheme.onPrimaryContainer),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: colorScheme.surface,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.primary,
        contentTextStyle: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outline),
      tabBarTheme: TabBarTheme(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
          insets: const EdgeInsets.symmetric(horizontal: 16),
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: colorScheme.surface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        showUnselectedLabels: true,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      iconTheme: IconThemeData(color: colorScheme.primary),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.primary,
        tileColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        fillColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected) ? colorScheme.primary : colorScheme.outline),
      ),
      radioTheme: RadioThemeData(
        fillColor: MaterialStateProperty.all(colorScheme.primary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected) ? colorScheme.primary : colorScheme.outline),
        trackColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected) ? colorScheme.primary.withOpacity(0.4) : colorScheme.outline.withOpacity(0.6)),
      ),
    );
  }
}

// Simple gradient helpers similar to MoMo headers
class MomoGradients {
  static LinearGradient headerPink([double opacity = 1]) => LinearGradient(
        colors: [
          const Color(0xFFFFCFE7).withOpacity(opacity),
          const Color(0xFFFFF4FA).withOpacity(opacity),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  static LinearGradient pillPink() => const LinearGradient(
        colors: [Color(0xFFE41C80), Color(0xFFFE58B6)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );
}
