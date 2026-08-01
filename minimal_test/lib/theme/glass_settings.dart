import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls the app's "Glass UI" appearance — on/off and blur intensity.
/// The glass *color* itself now comes from AppearanceSettings.accentColor,
/// so there's one color system for the whole app, not a separate one just
/// for glass mode.
class GlassSettings extends ChangeNotifier {
  static const _enabledKey = 'glass_ui_enabled';
  static const _blurKey = 'glass_ui_blur';

  bool _enabled = false;
  double _blur = 14.0;
  bool _loaded = false;

  bool get enabled => _enabled;
  double get blur => _blur;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _blur = prefs.getDouble(_blurKey) ?? 14.0;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_enabledKey, value);
  }

  Future<void> setBlur(double value) async {
    _blur = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_blurKey, value);
  }
}
