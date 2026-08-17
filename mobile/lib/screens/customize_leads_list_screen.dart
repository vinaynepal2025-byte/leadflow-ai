// CustomizeLeadsListScreen — show, hide, and reorder the optional fields
// on every Leads List row. Same backend-persisted-fields pattern as
// CustomizeDashboardScreen (lead_list_fields table, same shape as
// dashboard_sections), simplified further: no colour override, since
// these fields join into a plain subtitle line or render as fixed-style
// badges, not standalone colourable widgets.
import 'package:flutter/material.dart';
import '../services/api_service.dart';

const Map<String, String> kLeadListFieldLabels = {
  'field_phone': 'Phone number',
  'field_email': 'Email address',
  'field_source': 'Lead source',
  'field_assigned_to': 'Assigned counselor',
  'field_created_date': 'Created date',
  'badge_stage': 'Stage chip',
  'badge_score': 'Score badge',
};

const Map<String, IconData> kLeadListFieldIcons = {
  'field_phone': Icons.call_outlined,
  'field_email': Icons.email_outlined,
  'field_source': Icons.campaign_outlined,
  'field_assigned_to': Icons.person_outline,
  'field_created_date': Icons.calendar_today_outlined,
  'badge_stage': Icons.label_outline,
  'badge_score': Icons.local_fire_department_outlined,
};

// 'field_*' entries join into the row's subtitle line (in this order,
// separated by " · "); 'badge_*' entries render in the row's trailing
// column instead.
bool isLeadListBadge(String key) => key.startsWith('badge_');

class CustomizeLeadsListScreen extends StatefulWidget {
  const CustomizeLeadsListScreen({super.key});

  @override
  State<CustomizeLeadsListScreen> createState() => _CustomizeLeadsListScreenState();
}

class _CustomizeLeadsListScreenState extends State<CustomizeLeadsListScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _fields = [];
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
      final fields = await _api.getLeadListFields();
      if (!mounted) return;
      setState(() {
        _fields = fields;
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

  Future<void> _toggleEnabled(Map<String, dynamic> field, bool value) async {
    setState(() => field['enabled'] = value);
    try {
      await _api.updateLeadListField(field['field_key'], {'enabled': value});
    } catch (e) {
      setState(() => field['enabled'] = !value);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _move(int index, int delta) async {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _fields.length) return;
    setState(() {
      final item = _fields.removeAt(index);
      _fields.insert(newIndex, item);
    });
    try {
      await _api.reorderLeadListFields(_fields.map((f) => f['field_key'] as String).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reorder failed: $e')));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customize Leads List')),
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
                          'Show, hide, and reorder the fields on every lead row. "Phone/Email/Source/'
                          'Counselor/Date" join into the line under each name; "Stage chip/Score badge" '
                          'are the small tags on the right. Changes apply for all counselors on this account.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                      ..._fields.asMap().entries.map((entry) {
                        final index = entry.key;
                        final field = entry.value;
                        final key = field['field_key'] as String;
                        final label = kLeadListFieldLabels[key] ?? key;
                        final icon = kLeadListFieldIcons[key] ?? Icons.widgets_outlined;
                        final enabled = field['enabled'] as bool? ?? true;
                        final isBadge = isLeadListBadge(key);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(icon, color: enabled ? null : Colors.grey),
                            title: Text(label, style: TextStyle(color: enabled ? null : Colors.grey)),
                            subtitle: Text(isBadge ? 'Trailing badge' : 'Subtitle line',
                                style: const TextStyle(fontSize: 11)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                                  onPressed: index == 0 ? null : () => _move(index, -1),
                                  tooltip: 'Move up',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                                  onPressed: index == _fields.length - 1 ? null : () => _move(index, 1),
                                  tooltip: 'Move down',
                                ),
                                Switch(value: enabled, onChanged: (v) => _toggleEnabled(field, v)),
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
