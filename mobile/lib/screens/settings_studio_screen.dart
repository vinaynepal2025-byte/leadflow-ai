import 'package:flutter/material.dart';
import 'more_screen.dart' show kMoreMenuDefaults, kMoreMenuIconOptions;
import 'customize_more_menu_screen.dart';
import 'customize_lead_detail_screen.dart';
import 'customize_share_targets_screen.dart';
import 'customize_dashboard_screen.dart';
import 'customize_leads_list_screen.dart';

class _StudioItem {
  final String label;
  final IconData icon;
  final String category;
  final Color categoryColor;
  final Widget Function() screenBuilder;
  const _StudioItem({required this.label, required this.icon, required this.category, required this.categoryColor, required this.screenBuilder});
}

/// Every customizable button/section in the app, in one flat searchable
/// list -- the direct answer to "jaha main koi bhi button search karke
/// apne according customize kar saku". Built from the same default
/// label/icon maps each Customize* screen already keeps in sync with
/// its backend DEFAULTS (no extra network round-trip needed just to
/// populate a search index), tagged by which screen it lives on.
/// Tapping a result jumps straight into that item's real editor via
/// each screen's initialEditKey -- for More Menu / Lead Detail / Share
/// Targets, which have a full colour+icon+style editor per item, this
/// opens that editor sheet automatically; Dashboard and Leads List
/// don't have a matching per-item editor yet, so those land on the
/// customize screen itself instead.
List<_StudioItem> _buildRegistry() {
  final items = <_StudioItem>[];

  for (final entry in kMoreMenuDefaults.entries) {
    final key = entry.key;
    final def = entry.value;
    items.add(_StudioItem(
      label: def.label,
      icon: kMoreMenuIconOptions[def.icon] ?? Icons.star,
      category: 'More Menu',
      categoryColor: Colors.deepPurple,
      screenBuilder: () => CustomizeMoreMenuScreen(initialEditKey: key),
    ));
  }

  for (final entry in kLeadDetailDefaultLabels.entries) {
    final key = entry.key;
    items.add(_StudioItem(
      label: entry.value,
      icon: kLeadDetailIconOptions[kLeadDetailDefaultIcons[key]] ?? Icons.star,
      category: 'Lead Detail',
      categoryColor: Colors.indigo,
      screenBuilder: () => CustomizeLeadDetailScreen(initialEditKey: key),
    ));
  }

  for (final entry in kShareTargetDefaultLabels.entries) {
    final key = entry.key;
    items.add(_StudioItem(
      label: entry.value,
      icon: kShareTargetIconOptions[kShareTargetDefaultIcons[key]] ?? Icons.star,
      category: 'Share Targets',
      categoryColor: Colors.green,
      screenBuilder: () => CustomizeShareTargetsScreen(initialEditKey: key),
    ));
  }

  for (final entry in kDashboardSectionLabels.entries) {
    items.add(_StudioItem(
      label: entry.value,
      icon: kDashboardSectionIcons[entry.key] ?? Icons.star,
      category: 'Dashboard',
      categoryColor: Colors.blue,
      screenBuilder: () => const CustomizeDashboardScreen(),
    ));
  }

  for (final entry in kLeadListFieldLabels.entries) {
    items.add(_StudioItem(
      label: entry.value,
      icon: kLeadListFieldIcons[entry.key] ?? Icons.star,
      category: 'Leads List',
      categoryColor: Colors.teal,
      screenBuilder: () => const CustomizeLeadsListScreen(),
    ));
  }

  return items;
}

class SettingsStudioScreen extends StatefulWidget {
  const SettingsStudioScreen({super.key});

  @override
  State<SettingsStudioScreen> createState() => _SettingsStudioScreenState();
}

class _SettingsStudioScreenState extends State<SettingsStudioScreen> {
  late final List<_StudioItem> _registry = _buildRegistry();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? _registry
        : _registry.where((i) => i.label.toLowerCase().contains(q) || i.category.toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings Studio')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search any button or section to customize...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${results.length} customizable item${results.length == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: results.isEmpty
                ? const Center(child: Text('No matches', style: TextStyle(color: Colors.grey)))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = results[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: item.categoryColor.withValues(alpha: 0.12),
                          child: Icon(item.icon, color: item.categoryColor, size: 20),
                        ),
                        title: Text(item.label),
                        subtitle: Text(item.category, style: TextStyle(fontSize: 11, color: item.categoryColor)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => item.screenBuilder())),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
