// CustomizeLeadsListScreen — show, hide, and reorder the optional fields
// on every Leads List row. Same backend-persisted-fields pattern as
// CustomizeDashboardScreen (lead_list_fields table, same shape as
// dashboard_sections), simplified further: no colour override, since
// these fields join into a plain subtitle line or render as fixed-style
// badges, not standalone colourable widgets.
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/stage_chip.dart';
import '../widgets/launcher_tile.dart' show kTileTextureLabels;

// These two rows are style-only pseudo-fields (see backend/routes/
// leadListFields.js DEFAULTS) -- never shown in the toggleable/
// reorderable list, edited from the separate "Appearance" section below.
const Set<String> _kPseudoFieldKeys = {'card_container', 'bulk_action_bar'};

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

  /// Style editor for the Stage chip specifically -- the only "boxed"
  /// element among these 7 fields (the rest are plain subtitle text or,
  /// for the Score badge, unboxed icon+number). Deliberately doesn't
  /// offer a colour override: StageChip's colour is stage-coded
  /// information, not decoration, so only the structural controls
  /// (corner radius/border/glow/blur/size) are exposed, same reasoning
  /// as the widget itself.
  Future<void> _editStageChipStyle(Map<String, dynamic> field) async {
    final sj = Map<String, dynamic>.from((field['style_json'] as Map?) ?? {});
    double cornerRadius = ((sj['cornerRadius'] as num?)?.toDouble() ?? 20).clamp(0, 40);
    double borderWidth = ((sj['borderWidth'] as num?)?.toDouble() ?? 1.0).clamp(0, 6);
    double glowIntensity = ((sj['glowIntensity'] as num?)?.toDouble() ?? 0).clamp(0, 1);
    double blurAmount = ((sj['blurAmount'] as num?)?.toDouble() ?? 0).clamp(0, 12);
    double contentScale = ((sj['contentScale'] as num?)?.toDouble() ?? 1.0).clamp(0.8, 1.4);

    Widget sliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged,
        {String Function(double)? format}) {
      return Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
          SizedBox(
            width: 36,
            child: Text(format != null ? format(value) : value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.right),
          ),
        ],
      );
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stage chip style', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                Center(
                  child: StageChip(
                    stage: 'Enrolled',
                    styleJson: {
                      'cornerRadius': cornerRadius,
                      'borderWidth': borderWidth,
                      'glowIntensity': glowIntensity,
                      'blurAmount': blurAmount,
                      'contentScale': contentScale,
                    },
                  ),
                ),
                const SizedBox(height: 16),
                sliderRow('Sharpness', cornerRadius, 0, 40, (v) => setSheetState(() => cornerRadius = v)),
                sliderRow('Edge width', borderWidth, 0, 6, (v) => setSheetState(() => borderWidth = v)),
                sliderRow('Glow', glowIntensity, 0, 1, (v) => setSheetState(() => glowIntensity = v),
                    format: (v) => '${(v * 100).round()}%'),
                sliderRow('Blur', blurAmount, 0, 12, (v) => setSheetState(() => blurAmount = v)),
                sliderRow('Size', contentScale, 0.8, 1.4, (v) => setSheetState(() => contentScale = v),
                    format: (v) => '${(v * 100).round()}%'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true) return;

    final newStyle = {
      'cornerRadius': cornerRadius,
      'borderWidth': borderWidth,
      'glowIntensity': glowIntensity,
      'blurAmount': blurAmount,
      'contentScale': contentScale,
    };
    setState(() => field['style_json'] = newStyle);
    try {
      await _api.updateLeadListField(field['field_key'], {'style_json': newStyle});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save style: $e')));
    }
  }

  List<Map<String, dynamic>> get _toggleableFields =>
      _fields.where((f) => !_kPseudoFieldKeys.contains(f['field_key'])).toList();

  Map<String, dynamic> _fieldByKey(String key) =>
      _fields.firstWhere((f) => f['field_key'] == key, orElse: () => {'field_key': key, 'style_json': {}});

  /// Shared style editor for the two whole-element pseudo-fields (the
  /// lead card container, the bulk action bar) -- same slider set as
  /// _editStageChipStyle plus a texture picker (a whole card/bar has
  /// room for a background pattern in a way a small chip doesn't), no
  /// content-scale (there's no single icon/text pair to scale on a
  /// whole row).
  Future<void> _editContainerStyle(Map<String, dynamic> field, {required String title}) async {
    final sj = Map<String, dynamic>.from((field['style_json'] as Map?) ?? {});
    double cornerRadius = ((sj['cornerRadius'] as num?)?.toDouble() ?? 12).clamp(0, 40);
    double borderWidth = ((sj['borderWidth'] as num?)?.toDouble() ?? 1.0).clamp(0, 6);
    double glowIntensity = ((sj['glowIntensity'] as num?)?.toDouble() ?? 0).clamp(0, 1);
    double blurAmount = ((sj['blurAmount'] as num?)?.toDouble() ?? 0).clamp(0, 16);
    String textureId = (sj['textureId'] as String?) ?? 'none';

    Widget sliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged,
        {String Function(double)? format}) {
      return Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
          SizedBox(
            width: 36,
            child: Text(format != null ? format(value) : value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.right),
          ),
        ],
      );
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 16),
                sliderRow('Sharpness', cornerRadius, 0, 40, (v) => setSheetState(() => cornerRadius = v)),
                sliderRow('Edge width', borderWidth, 0, 6, (v) => setSheetState(() => borderWidth = v)),
                sliderRow('Glow', glowIntensity, 0, 1, (v) => setSheetState(() => glowIntensity = v),
                    format: (v) => '${(v * 100).round()}%'),
                sliderRow('Blur', blurAmount, 0, 16, (v) => setSheetState(() => blurAmount = v)),
                const SizedBox(height: 8),
                const Text('Texture', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kTileTextureLabels.entries.map((e) {
                    return ChoiceChip(
                      label: Text(e.value, style: const TextStyle(fontSize: 12)),
                      selected: e.key == textureId,
                      onSelected: (_) => setSheetState(() => textureId = e.key),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true) return;

    final newStyle = {
      'cornerRadius': cornerRadius,
      'borderWidth': borderWidth,
      'glowIntensity': glowIntensity,
      'blurAmount': blurAmount,
      'textureId': textureId,
    };
    final key = field['field_key'] as String;
    setState(() {
      final idx = _fields.indexWhere((f) => f['field_key'] == key);
      if (idx != -1) {
        _fields[idx] = {..._fields[idx], 'style_json': newStyle};
      } else {
        _fields.add({'field_key': key, 'style_json': newStyle, 'enabled': true});
      }
    });
    try {
      await _api.updateLeadListField(key, {'style_json': newStyle});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save style: $e')));
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
                      ..._toggleableFields.asMap().entries.map((entry) {
                        final field = entry.value;
                        final index = _fields.indexOf(field);
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
                                if (key == 'badge_stage')
                                  IconButton(
                                    icon: const Icon(Icons.brush_outlined, size: 20),
                                    tooltip: 'Style this chip',
                                    onPressed: () => _editStageChipStyle(field),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                                  onPressed: index == 0 ? null : () => _move(index, -1),
                                  tooltip: 'Move up',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                                  onPressed: index == _toggleableFields.length - 1 ? null : () => _move(index, 1),
                                  tooltip: 'Move down',
                                ),
                                Switch(value: enabled, onChanged: (v) => _toggleEnabled(field, v)),
                              ],
                            ),
                          ),
                        );
                      }),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.view_agenda_outlined),
                          title: const Text('Lead card look'),
                          subtitle: const Text('Corner radius, edge, glow, blur, texture for every row'),
                          trailing: IconButton(
                            icon: const Icon(Icons.brush_outlined, size: 20),
                            tooltip: 'Style',
                            onPressed: () => _editContainerStyle(_fieldByKey('card_container'), title: 'Lead card style'),
                          ),
                        ),
                      ),
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.select_all),
                          title: const Text('Bulk action buttons look'),
                          subtitle: const Text('Select All / Move / Delete, shown while multi-selecting'),
                          trailing: IconButton(
                            icon: const Icon(Icons.brush_outlined, size: 20),
                            tooltip: 'Style',
                            onPressed: () => _editContainerStyle(_fieldByKey('bulk_action_bar'), title: 'Bulk action bar style'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
    );
  }
}
