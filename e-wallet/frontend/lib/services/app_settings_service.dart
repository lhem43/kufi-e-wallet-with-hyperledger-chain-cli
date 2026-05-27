import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages app-level settings: theme mode, language.
/// Singleton with a ChangeNotifier so the MaterialApp can rebuild.
class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();
  static final AppSettingsService _instance = AppSettingsService._();
  factory AppSettingsService() => _instance;

  static const _keyThemeMode = 'app_theme_mode';  // 'light' | 'dark' | 'system'
  static const _keyLanguage = 'app_language';      // 'vi' | 'en'

  ThemeMode _themeMode = ThemeMode.light;
  String _language = 'vi';
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  String get language => _language;
  bool get isDark => _themeMode == ThemeMode.dark;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_keyThemeMode) ?? 'light';
    _themeMode = mode == 'dark' ? ThemeMode.dark : ThemeMode.light;
    _language = prefs.getString(_keyLanguage) ?? 'vi';
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyThemeMode, mode == ThemeMode.dark ? 'dark' : 'light');
  }

  Future<void> setLanguage(String lang) async {
    if (_language == lang) return;
    _language = lang;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, lang);
  }
}
