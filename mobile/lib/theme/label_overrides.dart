import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-tenant custom label overrides -- lets a person rename any
/// translatable string (nav tab labels, section titles, button text)
/// without touching the shared `_translations` dictionary in
/// app_strings.dart, which is multi-language content, not per-tenant
/// branding. This is a separate overlay: a set override always wins
/// over the language-translation lookup, checked first in `context.tr()`.
///
/// Stored as `key||value` pairs in a string list (same delimiter
/// pattern AppearanceSettings already uses for custom presets) rather
/// than JSON, to avoid adding a dart:convert import for one small
/// feature -- consistent with that existing precedent in this codebase.
class LabelOverrides extends ChangeNotifier {
  static const _prefsKey = 'custom_label_overrides';

  Map<String, String> _overrides = {};
  bool _loaded = false;

  bool get loaded => _loaded;
  Map<String, String> get all => Map.unmodifiable(_overrides);

  String? operator [](String key) => _overrides[key];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    final map = <String, String>{};
    for (final entry in raw) {
      final sep = entry.indexOf('||');
      if (sep == -1) continue;
      map[entry.substring(0, sep)] = entry.substring(sep + 2);
    }
    _overrides = map;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _overrides.entries.map((e) => '${e.key}||${e.value}').toList();
    await prefs.setStringList(_prefsKey, list);
  }

  Future<void> setOverride(String key, String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _overrides.remove(key);
    } else {
      _overrides[key] = trimmed;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> resetAll() async {
    _overrides = {};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
