import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/momo_theme.dart';
import '../theme/nature_theme.dart';
import '../theme/ocean_theme.dart';
import '../theme/sunset_theme.dart';
import '../theme/lavender_theme.dart';
import '../theme/midnight_theme.dart';

class ThemeProvider with ChangeNotifier {
  ThemeData? _currentTheme;
  String _currentThemeName = 'light';

  // Available themes
  static const List<String> availableThemes = [
    'light',
    'nature',
    'ocean',
    'sunset',
    'lavender',
    'midnight',
  ];
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
    notifyListeners();
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
      case 'ocean':
        _currentTheme = OceanTheme.light();
        _currentThemeName = 'ocean';
        break;
      case 'sunset':
        _currentTheme = SunsetTheme.light();
        _currentThemeName = 'sunset';
        break;
      case 'lavender':
        _currentTheme = LavenderTheme.light();
        _currentThemeName = 'lavender';
        break;
      case 'midnight':
        _currentTheme = MidnightTheme.dark();
        _currentThemeName = 'midnight';
        break;
      case 'light':
      default:
        _currentTheme = MomoTheme.light();
        _currentThemeName = 'light';
        break;
    }
  }
}