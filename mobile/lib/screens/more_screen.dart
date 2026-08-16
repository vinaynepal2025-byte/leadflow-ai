import 'package:flutter/material.dart';
import 'settings_screen.dart';
import 'performance_screen.dart';
import 'audit_screen.dart';
import 'knowledge_screen.dart';
import 'automations_screen.dart';
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
import '../services/api_service.dart';

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
};

Color _hexToColor(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('More')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final visibleItems = _items.where((i) => i['enabled'] != false).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Customize this menu',
            onPressed: _openCustomizer,
          ),
        ],
      ),
      body: ListView(
        children: [
          ...visibleItems.map((item) {
            final key = item['item_key'] as String;
            final def = kMoreMenuDefaults[key];
            final isCustom = item['is_custom'] == true;

            final label = item['custom_label'] ?? def?.label ?? key;
            final subtitle = def?.subtitle ?? '';
            final iconKey = item['icon_override'] ?? def?.icon ?? 'star';
            final icon = kMoreMenuIconOptions[iconKey] ?? Icons.star;
            final colorHex = item['color_override'] as String?;
            final color = colorHex != null ? _hexToColor(colorHex) : null;

            return ListTile(
              leading: Icon(icon, color: color),
              title: Text(label),
              subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
              onTap: () {
                if (isCustom) {
                  // Custom items are URL-only for now (matches
                  // backend validation) -- opening them in-app via a
                  // simple screen is a later slice; for now this is a
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
            );
          }),
        ],
      ),
    );
  }
}
