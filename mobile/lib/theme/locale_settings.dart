import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  english('en', 'English'),
  hindi('hi', 'हिन्दी'),
  nepali('ne', 'नेपाली');

  final String code;
  final String label;
  const AppLanguage(this.code, this.label);
}

/// The app's language — a personal device preference, persisted locally.
/// Flutter's built-in widgets (date pickers, etc.) only ship translations
/// for a subset of locales; Nepali isn't one of Flutter's own supported
/// Material locales, so those specific native dialogs fall back to
/// English even when AppLanguage.nepali is selected — every screen text
/// this app controls itself still translates correctly.
class LocaleSettings extends ChangeNotifier {
  static const _key = 'app_language';
  AppLanguage _language = AppLanguage.english;
  bool _loaded = false;

  AppLanguage get language => _language;
  bool get loaded => _loaded;
  Locale get locale => Locale(_language.code);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    _language = AppLanguage.values.firstWhere((l) => l.code == code, orElse: () => AppLanguage.english);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage lang) async {
    _language = lang;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString(_key, lang.code);
  }
}
