import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/edit_mode_settings.dart';
import 'settings_screen.dart';
import 'performance_screen.dart';
import 'audit_screen.dart';
import 'knowledge_screen.dart';
import 'automations_screen.dart';
import 'automation_center_screen.dart';
import 'calendar_screen.dart';
import 'colleges_screen.dart';
import 'team_screen.dart';
import 'parent_crm_screen.dart';
import 'flyer_studio/flyer_history_screen.dart';
import 'custom_fields_builder_screen.dart';
import 'pipeline_builder_screen.dart';
import 'social_links_screen.dart';
import 'capture_forms_screen.dart';
import 'scoring_config_screen.dart';
import 'triage_test_screen.dart';
import 'insights_overview_screen.dart';
import 'customize_more_menu_screen.dart';
import 'customize_registry.dart';
import '../services/api_service.dart';
import '../widgets/launcher_tile.dart';
import '../widgets/quick_style_editor_sheet.dart';

// Curated icon set for icon_override -- same string-key-to-IconData
// pattern as kLeadDetailIconOptions/kShareTargetIconOptions.
const Map<String, IconData> kMoreMenuIconOptions = {
  'auto_awesome_mosaic_outlined': Icons.auto_awesome_mosaic_outlined,
  'family_restroom_outlined': Icons.family_restroom_outlined,
  'groups_outlined': Icons.groups_outlined,
  'school_outlined': Icons.school_outlined,
  'calendar_month_outlined': Icons.calendar_month_outlined,
  'leaderboard_outlined': Icons.leaderboard_outlined,
  'history': Icons.history,
  'menu_book_outlined': Icons.menu_book_outlined,
  'bolt_outlined': Icons.bolt_outlined,
  'analytics_outlined': Icons.analytics_outlined,
  'smart_toy_outlined': Icons.smart_toy_outlined,
  'tune': Icons.tune,
  'qr_code_2_outlined': Icons.qr_code_2_outlined,
  'share_outlined': Icons.share_outlined,
  'view_kanban_outlined': Icons.view_kanban_outlined,
  'dashboard_customize_outlined': Icons.dashboard_customize_outlined,
  'settings_outlined': Icons.settings_outlined,
  'star': Icons.star,
  'link': Icons.link,
  'hub_outlined': Icons.hub_outlined,
};

// Default label + icon + subtitle + navigation target per built-in
// item_key. Must stay in sync with the DEFAULTS array in
// backend/routes/moreMenuItems.js -- same reasoning as the Lead Detail
// and Share Targets screens: the backend seeds the row but doesn't send
// a default label/icon/subtitle over the wire when overrides are null.
class _MoreMenuItemDef {
  final String label;
  final String subtitle;
  final String icon;
  final Widget Function() screenBuilder;
  const _MoreMenuItemDef(this.label, this.subtitle, this.icon, this.screenBuilder);
}

final Map<String, _MoreMenuItemDef> kMoreMenuDefaults = {
  'flyer_studio': _MoreMenuItemDef('Flyer Studio', 'Design and share promotional flyers', 'auto_awesome_mosaic_outlined', () => const FlyerHistoryScreen()),
  'parent_crm': _MoreMenuItemDef('Parent CRM', 'Leads with guardian contacts', 'family_restroom_outlined', () => const ParentCrmScreen()),
  'team': _MoreMenuItemDef('Team', 'Counselors & consultants', 'groups_outlined', () => const TeamScreen()),
  'colleges': _MoreMenuItemDef('Colleges & Universities', 'Partner institutions', 'school_outlined', () => const CollegesScreen()),
  'calendar': _MoreMenuItemDef('Calendar', 'Tasks & follow-ups by date', 'calendar_month_outlined', () => const CalendarScreen()),
  'performance': _MoreMenuItemDef('Performance', 'Counselor leaderboard', 'leaderboard_outlined', () => const PerformanceScreen()),
  'audit_timeline': _MoreMenuItemDef('Audit Timeline', 'All activity, one feed', 'history', () => const AuditScreen()),
  'knowledge_base': _MoreMenuItemDef('Knowledge Base', 'Visa/university guides', 'menu_book_outlined', () => const KnowledgeScreen()),
  'automation_hub': _MoreMenuItemDef('Automation Hub', 'Auto-reminders on triggers', 'bolt_outlined', () => const AutomationsScreen()),
  'insights_records': _MoreMenuItemDef('Insights & Records', 'Alumni links, college performance, data requests', 'analytics_outlined', () => const InsightsOverviewScreen()),
  'smart_triage': _MoreMenuItemDef('Smart Triage', 'Test AI auto-reply before enabling', 'smart_toy_outlined', () => const TriageTestScreen()),
  'lead_scoring': _MoreMenuItemDef('Lead Scoring Rules', 'Customize what makes a "hot" lead', 'tune', () => const ScoringConfigScreen()),
  'lead_capture_forms': _MoreMenuItemDef('Lead Capture Forms', 'Public forms for website/QR/social', 'qr_code_2_outlined', () => const CaptureFormsScreen()),
  'social_media_links': _MoreMenuItemDef('Social Media Links', 'Trackable links, QR codes, attribution', 'share_outlined', () => const SocialLinksScreen()),
  'pipeline_builder': _MoreMenuItemDef('Pipeline Builder', 'Customize your lead stages', 'view_kanban_outlined', () => const PipelineBuilderScreen()),
  'custom_fields': _MoreMenuItemDef('Custom Fields', 'Define your own lead fields', 'dashboard_customize_outlined', () => const CustomFieldsBuilderScreen()),
  'settings': _MoreMenuItemDef('Settings', 'Branding & contact info', 'settings_outlined', () => const SettingsScreen()),
  'automation_center': _MoreMenuItemDef('Automation Center', 'AI agents, auto mode, job queue', 'hub_outlined', () => const AutomationCenterScreen()),
};

Color _hexToColor(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

// Default per-item accent colours -- same idea as Lead Detail's
// _navActionFor default colours (Colors.green for WhatsApp, Colors.teal
// for Calls & Voice Notes, etc.): every built-in item gets its own
// distinct hue so the grid reads by colour+icon at a glance instead of
// every tile being an identical shade of the single global accent
// colour. A tenant's color_override still wins when set.
const Map<String, Color> kMoreMenuDefaultColors = {
  'flyer_studio': Colors.deepPurple,
  'parent_crm': Colors.pink,
  'team': Colors.blue,
  'colleges': Colors.indigo,
  'calendar': Colors.orange,
  'performance': Colors.green,
  'audit_timeline': Colors.blueGrey,
  'knowledge_base': Colors.brown,
  'automation_hub': Color(0xFFB8860B),
  'insights_records': Colors.teal,
  'smart_triage': Colors.cyan,
  'lead_scoring': Colors.redAccent,
  'lead_capture_forms': Color(0xFF0288D1),
  'social_media_links': Colors.purple,
  'pipeline_builder': Colors.deepOrange,
  'custom_fields': Color(0xFF558B2F),
  'settings': Colors.grey,
  'automation_center': Colors.lightGreen,
};

/// The More screen now reads its own tile list from the tenant's
/// /more-menu-items config -- enable/disable, reorder, rename, re-icon,
/// re-colour, all per-item, all persisted server-side. This is the
/// direct, working answer to "har smallest visible section par control
/// chahiye": the exact same proven pattern already shipped for Lead
/// Detail buttons and Share Targets, applied here.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _api.getMoreMenuItems();
      if (mounted) setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      // If config can't load, fall back to showing every built-in item
      // in its default order rather than an empty/broken menu -- the
      // menu staying usable matters more than the customization
      // reflecting perfectly during a transient network failure.
      if (mounted) setState(() {
        _items = kMoreMenuDefaults.entries
            .map((e) => {'item_key': e.key, 'enabled': true, 'is_custom': false})
            .toList();
        _loading = false;
      });
    }
  }

  void _openCustomizer() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomizeMoreMenuScreen()));
    _load();
  }

  // Built once, not per-build -- the registry is static data (labels/
  // icons/screen builders), only the live _items list above changes.
  late final List<CustomizeRegistryItem> _registry = buildCustomizeRegistry();

  Future<void> _openQuickEditor(Map<String, dynamic> item) async {
    final key = item['item_key'] as String;
    CustomizeRegistryItem? regItem;
    for (final r in _registry) {
      if (r.source == CustomizeSource.moreMenu && r.key == key) {
        regItem = r;
        break;
      }
    }
    if (regItem == null) return; // custom link items: no registry entry yet

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuickStyleEditorSheet(
        item: regItem!,
        currentColorHex: (item['color_override'] as String?) ?? '#1B2A4A',
        currentStyleVariant: (item['style_variant'] as String?) ?? 'flat',
        currentGradientEndHex: item['gradient_override'] as String?,
        currentStyleJson: (item['style_json'] as Map?)?.cast<String, dynamic>(),
        currentIconImageUrl: item['icon_image_url'] as String?,
      ),
    );
    if (result == null) return;
    // Live update -- reflect the new look immediately, no re-fetch wait.
    setState(() {
      final idx = _items.indexWhere((i) => i['item_key'] == key);
      if (idx != -1) {
        _items[idx] = {
          ..._items[idx],
          'color_override': result['color'],
          'style_variant': result['styleVariant'],
          'gradient_override': result['gradientEnd'],
          'style_json': result['styleJson'],
          'icon_image_url': result['iconImageUrl'],
        };
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('More')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final visibleItems = _items.where((i) => i['enabled'] != false).toList();

    final editMode = context.watch<EditModeSettings>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        actions: [
          IconButton(
            icon: Icon(editMode.enabled ? Icons.edit : Icons.edit_outlined),
            tooltip: editMode.enabled ? 'Exit Edit Mode' : 'Edit Mode -- tap any tile to restyle it live',
            color: editMode.enabled ? Theme.of(context).colorScheme.primary : null,
            onPressed: editMode.toggle,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Customize this menu',
            onPressed: _openCustomizer,
          ),
        ],
      ),
      // Colourful card grid -- previously a plain single-colour ListTile
      // list, which read as noticeably flatter/less premium than the
      // Lead Detail screen's Modules grid right next to it in the same
      // app. Now built on the exact same tile-card visual language
      // (tinted/gradient/glow/glass background + colour-matched icon)
      // so every "grid of destinations" screen in the app looks like
      // one consistent, premium design system rather than two.
      body: Column(
        children: [
          if (editMode.enabled)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Edit Mode is on -- tap any tile to restyle it live', style: TextStyle(fontSize: 12))),
                ],
              ),
            ),
          Expanded(child: _buildGrid(visibleItems)),
        ],
      ),
    );
  }

  // A Wrap, not GridView.count -- a fixed 3-column grid forces every tile
  // to the same cell size, which is exactly the "sirf width control diya
  // hai" limitation reported: no way to make one tile full-width, another
  // a tall square, another short and wide. Wrap lets each tile pick its
  // own [widthFraction] (of the available row width) and [tileHeight] (in
  // logical pixels) independently via style_json, flowing left-to-right
  // and wrapping naturally -- genuinely free per-tile sizing, not another
  // fixed preset. When neither override is set, the computed default here
  // reproduces the exact width/height the old GridView.count(crossAxisCount:
  // 3, childAspectRatio: 0.92) produced, so nothing visually changes for a
  // tile until the user actually resizes it.
  Widget _buildGrid(List<Map<String, dynamic>> visibleItems) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final defaultCellWidth = (constraints.maxWidth - 2 * spacing) / 3;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: visibleItems.map((item) {
              final key = item['item_key'] as String;
              final def = kMoreMenuDefaults[key];
              final isCustom = item['is_custom'] == true;

              final label = item['custom_label'] ?? def?.label ?? key;
              final iconKey = item['icon_override'] ?? def?.icon ?? 'star';
              final icon = kMoreMenuIconOptions[iconKey] ?? Icons.star;
              final iconImageUrl = item['icon_image_url'] as String?;
              final colorHex = item['color_override'] as String?;
              final color = colorHex != null ? _hexToColor(colorHex) : (kMoreMenuDefaultColors[key] ?? Theme.of(context).colorScheme.primary);
              final gradientHex = item['gradient_override'] as String?;
              final gradientEnd = gradientHex != null ? _hexToColor(gradientHex) : null;
              final styleVariant = item['style_variant'] as String? ?? 'flat';
              final styleJson = (item['style_json'] as Map?)?.cast<String, dynamic>();

              final widthFraction = (styleJson?['widthFraction'] as num?)?.toDouble();
              final tileWidth = widthFraction != null
                  ? (constraints.maxWidth * widthFraction).clamp(60.0, constraints.maxWidth)
                  : defaultCellWidth;
              final explicitHeight = (styleJson?['tileHeight'] as num?)?.toDouble();
              final tileHeight = explicitHeight ?? (tileWidth / 0.92);

              return SizedBox(
                width: tileWidth,
                height: tileHeight,
                child: LauncherTile(
                  label: label,
                  icon: icon,
                  iconImageUrl: iconImageUrl,
                  color: color,
                  gradientEnd: gradientEnd,
                  styleVariant: styleVariant,
                  styleJson: styleJson,
                  onEditTap: isCustom ? null : () => _openQuickEditor(item),
                  onTap: () {
                    if (isCustom) {
                      // Custom items are URL-only for now (matches backend
                      // validation) -- opening them in-app via a simple
                      // screen is a later slice; for now this is a
                      // clearly-scoped no-op rather than a silent failure.
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Custom link items will open in a later update')),
                      );
                      return;
                    }
                    if (def != null) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => def.screenBuilder()));
                    }
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
