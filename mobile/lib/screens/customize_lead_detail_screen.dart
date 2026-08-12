import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/color_picker_dialog.dart';

// Curated icon set for icon_override. Storing IconData directly isn't
// reliably serializable, so we store a string KEY in the DB and look up
// the real IconData here on the Dart side -- same pattern as any
// string-enum-to-widget mapping.
const Map<String, IconData> kLeadDetailIconOptions = {
  'auto_awesome': Icons.auto_awesome,
  'bolt': Icons.bolt,
  'chat': Icons.chat,
  'folder_outlined': Icons.folder_outlined,
  'school_outlined': Icons.school_outlined,
  'phone_in_talk_outlined': Icons.phone_in_talk_outlined,
  'event_available_outlined': Icons.event_available_outlined,
  'flight_takeoff_outlined': Icons.flight_takeoff_outlined,
  'diversity_3_outlined': Icons.diversity_3_outlined,
  'privacy_tip_outlined': Icons.privacy_tip_outlined,
  'star': Icons.star,
  'favorite': Icons.favorite,
  'call': Icons.call,
  'email_outlined': Icons.email_outlined,
  'work_outline': Icons.work_outline,
  'description_outlined': Icons.description_outlined,
  'payments_outlined': Icons.payments_outlined,
  'group_outlined': Icons.group_outlined,
  'shield_outlined': Icons.shield_outlined,
  'map_outlined': Icons.map_outlined,
};

// Default label + icon per built-in section_key. Must stay in sync with
// the DEFAULTS array in backend/routes/leadDetailSections.js -- the
// backend seeds the row but doesn't send a default label string over the
// wire when custom_label is null, so both sides carry this small map.
const Map<String, String> kLeadDetailDefaultLabels = {
  'ai_insight': 'AI Insight',
  'calling_cockpit': 'Open Calling Cockpit',
  'whatsapp': 'Send WhatsApp (free)',
  'documents': 'Documents',
  'admissions_fees': 'Admissions & Fees',
  'calls_voice_notes': 'Calls & Voice Notes',
  'meetings': 'Meetings & Campus Tours',
  'visa_travel_student': 'Visa, Travel & Student',
  'alumni': 'Alumni Network',
  'consent_compliance': 'Consent & Compliance',
  'lead_notes': 'Notes',
  'flyer_studio': 'Make a Flyer',
};

const Map<String, String> kLeadDetailDefaultIcons = {
  'ai_insight': 'auto_awesome',
  'calling_cockpit': 'bolt',
  'whatsapp': 'chat',
  'documents': 'folder_outlined',
  'admissions_fees': 'school_outlined',
  'calls_voice_notes': 'phone_in_talk_outlined',
  'meetings': 'event_available_outlined',
  'visa_travel_student': 'flight_takeoff_outlined',
  'alumni': 'diversity_3_outlined',
  'consent_compliance': 'privacy_tip_outlined',
  'lead_notes': 'description_outlined',
  'flyer_studio': 'auto_awesome_mosaic_outlined',
};

class CustomizeLeadDetailScreen extends StatefulWidget {
  const CustomizeLeadDetailScreen({super.key});

  @override
  State<CustomizeLeadDetailScreen> createState() => _CustomizeLeadDetailScreenState();
}

class _CustomizeLeadDetailScreenState extends State<CustomizeLeadDetailScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _sections = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sections = await _api.getLeadDetailSections();
    if (!mounted) return;
    setState(() {
      _sections = sections;
      _loading = false;
    });
  }

  Future<void> _toggleEnabled(Map<String, dynamic> section, bool value) async {
    setState(() => section['enabled'] = value);
    try {
      await _api.updateLeadDetailSection(section['section_key'], {'enabled': value});
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
      await _api.reorderLeadDetailSections(_sections.map((s) => s['section_key'] as String).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reorder failed: $e')));
      _load();
    }
  }

  Future<void> _openEditor(Map<String, dynamic> section) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SectionEditorSheet(section: section),
    );
    if (result != null) {
      setState(() {
        final idx = _sections.indexWhere((s) => s['section_key'] == section['section_key']);
        if (idx != -1) _sections[idx] = {..._sections[idx], ...result};
      });
      try {
        await _api.updateLeadDetailSection(section['section_key'], result);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
        _load();
      }
    }
  }

  Future<void> _deleteCustomSection(Map<String, dynamic> section) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this button?'),
        content: Text('"${section['custom_label']}" will be removed for everyone on this account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _api.deleteLeadDetailSection(section['section_key']);
      _load();
    }
  }

  Future<void> _addCustomButton() async {
    final labelCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    String actionType = 'url';

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add custom button', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(labelText: 'Button label', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 16),
                const Text('Action type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'url', label: Text('Link'), icon: Icon(Icons.link, size: 16)),
                    ButtonSegment(value: 'phone', label: Text('Call'), icon: Icon(Icons.call, size: 16)),
                    ButtonSegment(value: 'email', label: Text('Email'), icon: Icon(Icons.email_outlined, size: 16)),
                  ],
                  selected: {actionType},
                  onSelectionChanged: (s) => setSheetState(() => actionType = s.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: valueCtrl,
                  keyboardType: actionType == 'phone' ? TextInputType.phone : (actionType == 'email' ? TextInputType.emailAddress : TextInputType.url),
                  decoration: InputDecoration(
                    labelText: actionType == 'url' ? 'URL (https://...)' : (actionType == 'phone' ? 'Phone number' : 'Email address'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Add'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == true && labelCtrl.text.trim().isNotEmpty && valueCtrl.text.trim().isNotEmpty) {
      try {
        await _api.createLeadDetailSection(
          customLabel: labelCtrl.text.trim(),
          actionType: actionType,
          actionValue: valueCtrl.text.trim(),
        );
        await _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customize Lead Detail')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(
                      'Show, hide, reorder, and restyle the buttons on every Lead Detail screen. Changes apply for all counselors on this account.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                  ..._sections.asMap().entries.map((entry) {
                    final index = entry.key;
                    final section = entry.value;
                    final key = section['section_key'] as String;
                    final label = section['custom_label'] ?? kLeadDetailDefaultLabels[key] ?? key;
                    final iconKey = section['icon_override'] ?? kLeadDetailDefaultIcons[key] ?? 'star';
                    final icon = kLeadDetailIconOptions[iconKey] ?? Icons.star;
                    final colorHex = section['color_override'] as String?;
                    final color = colorHex != null ? _hexToColor(colorHex) : Theme.of(context).colorScheme.primary;
                    final enabled = section['enabled'] as bool? ?? true;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(icon, color: enabled ? color : Colors.grey),
                        title: Text(label, style: TextStyle(color: enabled ? null : Colors.grey)),
                        subtitle: section['is_custom'] == true ? const Text('Custom button', style: TextStyle(fontSize: 11)) : null,
                        onTap: () => _openEditor(section),
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
                              onPressed: index == _sections.length - 1 ? null : () => _move(index, 1),
                              tooltip: 'Move down',
                            ),
                            Switch(value: enabled, onChanged: (v) => _toggleEnabled(section, v)),
                            if (section['is_custom'] == true)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                tooltip: 'Delete',
                                onPressed: () => _deleteCustomSection(section),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add custom button'),
                    onPressed: _addCustomButton,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Color _hexToColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }
}

class _SectionEditorSheet extends StatefulWidget {
  final Map<String, dynamic> section;
  const _SectionEditorSheet({required this.section});

  @override
  State<_SectionEditorSheet> createState() => _SectionEditorSheetState();
}

class _SectionEditorSheetState extends State<_SectionEditorSheet> {
  late TextEditingController _labelCtrl;
  late String _iconKey;
  late Color _color;
  late String _size;
  late String _shape;

  @override
  void initState() {
    super.initState();
    final key = widget.section['section_key'] as String;
    _labelCtrl = TextEditingController(text: widget.section['custom_label'] ?? kLeadDetailDefaultLabels[key] ?? key);
    _iconKey = widget.section['icon_override'] ?? kLeadDetailDefaultIcons[key] ?? 'star';
    final colorHex = widget.section['color_override'] as String?;
    _color = colorHex != null ? _hexToColor(colorHex) : Colors.deepPurple;
    _size = widget.section['size_override'] ?? 'standard';
    _shape = widget.section['shape_override'] ?? 'rounded';
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

  Future<void> _pickColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initial: _color, title: 'Button color'),
    );
    if (picked != null) setState(() => _color = picked);
  }

  void _save() {
    Navigator.pop(context, {
      'custom_label': _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
      'icon_override': _iconKey,
      'color_override': _colorToHex(_color),
      'size_override': _size,
      'shape_override': _shape,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Customize button', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(labelText: 'Label', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 16),
            const Text('Icon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: kLeadDetailIconOptions.entries.map((e) {
                final selected = e.key == _iconKey;
                return GestureDetector(
                  onTap: () => setState(() => _iconKey = e.key),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? _color.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.08),
                      border: selected ? Border.all(color: _color, width: 2) : null,
                    ),
                    child: Icon(e.value, size: 20, color: selected ? _color : Colors.grey[700]),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                GestureDetector(
                  onTap: _pickColor,
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: _color, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Button size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'compact', label: Text('Compact')),
                ButtonSegment(value: 'standard', label: Text('Standard')),
                ButtonSegment(value: 'large', label: Text('Large')),
              ],
              selected: {_size},
              onSelectionChanged: (s) => setState(() => _size = s.first),
            ),
            const SizedBox(height: 16),
            const Text('Button shape', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'rounded', label: Text('Rounded')),
                ButtonSegment(value: 'square', label: Text('Square')),
                ButtonSegment(value: 'pill', label: Text('Pill')),
              ],
              selected: {_shape},
              onSelectionChanged: (s) => setState(() => _shape = s.first),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(onPressed: _save, child: const Text('Save'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
