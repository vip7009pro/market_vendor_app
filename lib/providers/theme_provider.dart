import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/momo_theme.dart';
import '../theme/nature_theme.dart';

class ThemeProvider with ChangeNotifier {
  ThemeData? _currentTheme;
  String _currentThemeName = 'light';

  // Available themes
  static const List<String> availableThemes = ['light', 'nature'];
  String get currentThemeName => _currentThemeName;

  ThemeProvider() {
    _loadTheme();
  }

  ThemeData get currentTheme {
    return _currentTheme ?? MomoTheme.light();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedThemeName = prefs.getString('app_theme') ?? 'light';
    _setTheme(savedThemeName);
  }

  Future<void> setTheme(String themeName) async {
    if (_currentThemeName == themeName) return;
    
    _setTheme(themeName);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme', themeName);
  }

  void _setTheme(String themeName) {
    switch (themeName) {      
      case 'nature':
        _currentTheme = NatureTheme.light();
        _currentThemeName = 'nature';
        break;
      case 'light':
      default:
        _currentTheme = MomoTheme.light();
        _currentThemeName = 'light';
        break;
    }
  }
}