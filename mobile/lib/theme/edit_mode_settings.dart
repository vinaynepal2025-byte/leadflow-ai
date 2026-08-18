import 'package:flutter/material.dart';

/// Whether the app is currently in "Edit Mode" -- the live design-mode
/// overlay the user asked for: "koi bhi button/tab/card ka look apne
/// hisaab se design kar sake aur wo effects live app mein change kar
/// sake". While on, any customizable tile (More Menu items today; more
/// registries can opt in later) shows a small pencil badge and tapping
/// it opens a quick style editor right there instead of navigating --
/// no separate "Customize X" screen detour needed.
///
/// Deliberately NOT persisted (no SharedPreferences) -- edit mode is a
/// short task someone turns on, does a few tweaks, then turns back off;
/// persisting it risks a person reopening the app days later confused
/// why buttons stopped navigating.
class EditModeSettings extends ChangeNotifier {
  bool _enabled = false;
  bool get enabled => _enabled;

  void toggle() {
    _enabled = !_enabled;
    notifyListeners();
  }

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }
}
