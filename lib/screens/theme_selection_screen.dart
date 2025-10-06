import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Thêm import để lưu theme
import '../providers/theme_provider.dart';

class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentTheme = themeProvider.currentThemeName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn giao diện'),
      ),
      body: ListView.builder(
        itemCount: ThemeProvider.availableThemes.length,
        itemBuilder: (context, index) {
          final themeName = ThemeProvider.availableThemes[index];
          return RadioListTile<String>(
            title: Text(
              _getThemeDisplayName(themeName),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            value: themeName,
            groupValue: currentTheme,
            onChanged: (value) async {
              if (value != null) {
                await themeProvider.setTheme(value);
                // Lưu theme vào SharedPreferences
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('selected_theme', value);
                // Update the UI immediately
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
          );
        },
      ),
    );
  }

  String _getThemeDisplayName(String themeName) {
    switch (themeName) {
      case 'light':
        return 'Hồng mộng mơ';
      case 'dark':
        return 'Tối';
      case 'nature':
        return 'Thiên nhiên';
      default:
        return themeName;
    }
  }
}