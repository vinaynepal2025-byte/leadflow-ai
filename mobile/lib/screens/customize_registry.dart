import 'package:flutter/material.dart';
import 'more_screen.dart' show kMoreMenuDefaults, kMoreMenuIconOptions;
import 'customize_more_menu_screen.dart';
import 'customize_lead_detail_screen.dart';
import 'customize_share_targets_screen.dart';
import 'customize_dashboard_screen.dart';
import 'customize_leads_list_screen.dart';
import '../services/api_service.dart';

/// Which backend PATCH call applies a style change for this item, and
/// with what key -- lets a caller (Settings Studio search, AI Quick
/// Restyle) apply an update without needing to know each screen's own
/// ApiService method name.
enum CustomizeSource { moreMenu, leadDetail, shareTargets, dashboard, leadsList }

/// One customizable button/section, wherever it lives in the app.
/// Shared between Settings Studio (browse/search) and AI Quick Restyle
/// (natural-language command -> match this item -> apply just its
/// style), so both features draw from exactly one registry instead of
/// two copies that could drift apart.
class CustomizeRegistryItem {
  final String key;
  final String label;
  final IconData icon;
  final String category;
  final Color categoryColor;
  final CustomizeSource source;
  final Widget Function() screenBuilder;
  const CustomizeRegistryItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.category,
    required this.categoryColor,
    required this.source,
    required this.screenBuilder,
  });

  /// Applies a style update to this specific item via the right
  /// backend route for its source -- used by AI Quick Restyle so a
  /// command changes only this one section, nothing else. Not used by
  /// Settings Studio, which instead opens the item's own editor sheet
  /// for a full manual edit.
  Future<void> applyStyle(
    ApiService api, {
    String? colorHex,
    String? styleVariant,
    String? gradientEndHex,
    Map<String, dynamic>? styleJson,
  }) async {
    final updates = <String, dynamic>{
      if (colorHex != null) 'color_override': colorHex,
      if (styleVariant != null) 'style_variant': styleVariant,
      if (gradientEndHex != null) 'gradient_override': gradientEndHex,
      if (styleJson != null) 'style_json': styleJson,
    };
    switch (source) {
      case CustomizeSource.moreMenu:
        await api.updateMoreMenuItem(key, updates);
        break;
      case CustomizeSource.leadDetail:
        await api.updateLeadDetailSection(key, updates);
        break;
      case CustomizeSource.shareTargets:
        await api.updateShareTarget(key, updates);
        break;
      case CustomizeSource.dashboard:
      case CustomizeSource.leadsList:
        // No per-item colour/style slot on these two yet (Dashboard only
        // has a fixed accent-colour override, Leads List has none) --
        // AI Quick Restyle's caller is expected to filter these out
        // before offering an apply action.
        throw UnsupportedError('$source items do not support colour/style overrides yet');
    }
  }
}

List<CustomizeRegistryItem> buildCustomizeRegistry() {
  final items = <CustomizeRegistryItem>[];

  for (final entry in kMoreMenuDefaults.entries) {
    final key = entry.key;
    final def = entry.value;
    items.add(CustomizeRegistryItem(
      key: key,
      label: def.label,
      icon: kMoreMenuIconOptions[def.icon] ?? Icons.star,
      category: 'More Menu',
      categoryColor: Colors.deepPurple,
      source: CustomizeSource.moreMenu,
      screenBuilder: () => CustomizeMoreMenuScreen(initialEditKey: key),
    ));
  }

  for (final entry in kLeadDetailDefaultLabels.entries) {
    final key = entry.key;
    items.add(CustomizeRegistryItem(
      key: key,
      label: entry.value,
      icon: kLeadDetailIconOptions[kLeadDetailDefaultIcons[key]] ?? Icons.star,
      category: 'Lead Detail',
      categoryColor: Colors.indigo,
      source: CustomizeSource.leadDetail,
      screenBuilder: () => CustomizeLeadDetailScreen(initialEditKey: key),
    ));
  }

  for (final entry in kShareTargetDefaultLabels.entries) {
    final key = entry.key;
    items.add(CustomizeRegistryItem(
      key: key,
      label: entry.value,
      icon: kShareTargetIconOptions[kShareTargetDefaultIcons[key]] ?? Icons.star,
      category: 'Share Targets',
      categoryColor: Colors.green,
      source: CustomizeSource.shareTargets,
      screenBuilder: () => CustomizeShareTargetsScreen(initialEditKey: key),
    ));
  }

  for (final entry in kDashboardSectionLabels.entries) {
    items.add(CustomizeRegistryItem(
      key: entry.key,
      label: entry.value,
      icon: kDashboardSectionIcons[entry.key] ?? Icons.star,
      category: 'Dashboard',
      categoryColor: Colors.blue,
      source: CustomizeSource.dashboard,
      screenBuilder: () => const CustomizeDashboardScreen(),
    ));
  }

  for (final entry in kLeadListFieldLabels.entries) {
    items.add(CustomizeRegistryItem(
      key: entry.key,
      label: entry.value,
      icon: kLeadListFieldIcons[entry.key] ?? Icons.star,
      category: 'Leads List',
      categoryColor: Colors.teal,
      source: CustomizeSource.leadsList,
      screenBuilder: () => const CustomizeLeadsListScreen(),
    ));
  }

  return items;
}

/// Finds the registry item whose label best matches free-form text (an
/// AI Quick Restyle command, or a search query) -- longest label whose
/// significant words all appear in the text wins, so "make the whatsapp
/// share button glow green" matches "WhatsApp" (Share Targets) rather
/// than nothing or the wrong item. Returns null when nothing scores.
CustomizeRegistryItem? findBestMatch(List<CustomizeRegistryItem> registry, String text) {
  final lower = text.toLowerCase();
  CustomizeRegistryItem? best;
  int bestScore = 0;
  for (final item in registry) {
    final words = item.label.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 2);
    if (words.isEmpty) continue;
    final matchedWords = words.where(lower.contains).length;
    if (matchedWords == 0) continue;
    // Score favours matching a larger fraction of the label's words,
    // then label length as a tiebreaker (a fuller, more specific label
    // match beats a shorter generic one that happens to share a word).
    final score = matchedWords * 100 ~/ words.length * 1000 + item.label.length;
    if (score > bestScore) {
      bestScore = score;
      best = item;
    }
  }
  return best;
}
