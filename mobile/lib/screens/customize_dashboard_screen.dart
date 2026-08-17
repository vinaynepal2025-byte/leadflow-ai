// CustomizeDashboardScreen — show/hide, reorder, and recolour the
// Dashboard's widgets. Same backend-persisted-sections pattern as
// CustomizeLeadDetailScreen (dashboard_sections table, same shape as
// lead_detail_sections), simplified for the Dashboard's case: every
// section is a fixed built-in widget (no user-created custom buttons),
// so there's no add/delete flow -- only enabled, sort_order, and an
// optional accent-colour override on the four metric cards.
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/color_picker_dialog.dart';

const Map<String, String> kDashboardSectionLabels = {
  'work_queue': 'Work Queue button',
  'metric_total_leads': 'Total Leads card',
  'metric_conversion': 'Conversion Rate card',
  'metric_pending_followups': 'Pending Follow-ups card',
  'metric_overdue': 'Overdue card',
  'pipeline_breakdown': 'Pipeline Breakdown chart',
};

const Map<String, IconData> kDashboardSectionIcons = {
  'work_queue': Icons.bolt,
  'metric_total_leads': Icons.people_outline,
  'metric_conversion': Icons.trending_up,
  'metric_pending_followups': Icons.alarm_outlined,
  'metric_overdue': Icons.priority_high,
  'pipeline_breakdown': Icons.bar_chart,
};

// Only the four metric cards render with a single, swappable accent
// colour -- the Work Queue button and the pipeline chart don't have an
// equivalent single-colour slot in their layout.
const Set<String> kDashboardColorizableSections = {
  'metric_total_leads',
  'metric_conversion',
  'metric_pending_followups',
  'metric_overdue',
};

class CustomizeDashboardScreen extends StatefulWidget {
  const CustomizeDashboardScreen({super.key});

  @override
  State<CustomizeDashboardScreen> createState() => _CustomizeDashboardScreenState();
}

class _CustomizeDashboardScreenState extends State<CustomizeDashboardScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _sections = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sections = await _api.getDashboardSections();
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load: $e';
        _loading = false;
      });
    }
  }

  Future<void> _toggleEnabled(Map<String, dynamic> section, bool value) async {
    setState(() => section['enabled'] = value);
    try {
      await _api.updateDashboardSection(section['section_key'], {'enabled': value});
    } catch (e) {
      setState(() => section['enabled'] = !value);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _move(int index, int delta) async {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _sections.length) return;
    setState(() {
      final item = _sections.removeAt(index);
      _sections.insert(newIndex, item);
    });
    try {
      await _api.reorderDashboardSections(_sections.map((s) => s['section_key'] as String).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reorder failed: $e')));
      _load();
    }
  }

  Future<void> _pickColor(Map<String, dynamic> section) async {
    final colorHex = section['color_override'] as String?;
    final initial = colorHex != null ? _hexToColor(colorHex) : Colors.deepPurple;
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initial: initial, title: 'Card accent colour'),
    );
    if (picked == null) return;
    final hex = _colorToHex(picked);
    setState(() => section['color_override'] = hex);
    try {
      await _api.updateDashboardSection(section['section_key'], {'color_override': hex});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      _load();
    }
  }

  Future<void> _resetColor(Map<String, dynamic> section) async {
    setState(() => section['color_override'] = null);
    try {
      await _api.updateDashboardSection(section['section_key'], {'color_override': null});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      _load();
    }
  }

  Color _hexToColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }

  String _colorToHex(Color c) {
    final v = c.value & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customize Dashboard')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text(
                          'Show, hide, reorder, and recolour the widgets on your Dashboard. Changes apply for all counselors on this account.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                      ..._sections.asMap().entries.map((entry) {
                        final index = entry.key;
                        final section = entry.value;
                        final key = section['section_key'] as String;
                        final label = kDashboardSectionLabels[key] ?? key;
                        final icon = kDashboardSectionIcons[key] ?? Icons.widgets_outlined;
                        final enabled = section['enabled'] as bool? ?? true;
                        final colorHex = section['color_override'] as String?;
                        final canColorize = kDashboardColorizableSections.contains(key);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(icon, color: enabled ? (colorHex != null ? _hexToColor(colorHex) : null) : Colors.grey),
                            title: Text(label, style: TextStyle(color: enabled ? null : Colors.grey)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (canColorize)
                                  IconButton(
                                    icon: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: colorHex != null ? _hexToColor(colorHex) : Colors.grey.shade300,
                                        border: Border.all(color: Colors.grey.shade400),
                                      ),
                                    ),
                                    tooltip: colorHex != null ? 'Change colour' : 'Set colour',
                                    onPressed: () => _pickColor(section),
                                  ),
                                if (canColorize && colorHex != null)
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    tooltip: 'Reset to default colour',
                                    onPressed: () => _resetColor(section),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                                  onPressed: index == 0 ? null : () => _move(index, -1),
                                  tooltip: 'Move up',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                                  onPressed: index == _sections.length - 1 ? null : () => _move(index, 1),
                                  tooltip: 'Move down',
                                ),
                                Switch(value: enabled, onChanged: (v) => _toggleEnabled(section, v)),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
    );
  }
}
