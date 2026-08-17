import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/color_picker_dialog.dart';

// Curated icon set for icon_override -- same string-key-to-IconData
// pattern as kLeadDetailIconOptions in customize_lead_detail_screen.dart,
// since IconData isn't reliably serializable to store directly.
const Map<String, IconData> kShareTargetIconOptions = {
  'chat': Icons.chat,
  'camera_alt_outlined': Icons.camera_alt_outlined,
  'facebook': Icons.facebook,
  'send_outlined': Icons.send_outlined,
  'email_outlined': Icons.email_outlined,
  'more_horiz': Icons.more_horiz,
  'link': Icons.link,
  'share_outlined': Icons.share_outlined,
  'public': Icons.public,
  'star': Icons.star,
};

// Default label + icon per built-in target_key. Must stay in sync with
// the DEFAULTS array in backend/routes/shareTargets.js -- same reasoning
// as kLeadDetailDefaultLabels: the backend seeds the row but doesn't
// send a default label when custom_label is null.
const Map<String, String> kShareTargetDefaultLabels = {
  'whatsapp': 'WhatsApp',
  'instagram': 'Instagram',
  'facebook': 'Facebook',
  'telegram': 'Telegram',
  'email': 'Email',
  'more': 'More apps...',
};

const Map<String, String> kShareTargetDefaultIcons = {
  'whatsapp': 'chat',
  'instagram': 'camera_alt_outlined',
  'facebook': 'facebook',
  'telegram': 'send_outlined',
  'email': 'email_outlined',
  'more': 'more_horiz',
};

class CustomizeShareTargetsScreen extends StatefulWidget {
  // Set when arriving from Settings Studio's search -- see the matching
  // comment on CustomizeMoreMenuScreen.initialEditKey for why.
  final String? initialEditKey;
  const CustomizeShareTargetsScreen({super.key, this.initialEditKey});

  @override
  State<CustomizeShareTargetsScreen> createState() => _CustomizeShareTargetsScreenState();
}

class _CustomizeShareTargetsScreenState extends State<CustomizeShareTargetsScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _targets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final targets = await _api.getShareTargets();
    if (!mounted) return;
    setState(() {
      _targets = targets;
      _loading = false;
    });
    if (widget.initialEditKey != null) {
      for (final target in _targets) {
        if (target['target_key'] == widget.initialEditKey) {
          _openEditor(target);
          break;
        }
      }
    }
  }

  Future<void> _toggleEnabled(Map<String, dynamic> target, bool value) async {
    setState(() => target['enabled'] = value);
    try {
      await _api.updateShareTarget(target['target_key'], {'enabled': value});
    } catch (e) {
      setState(() => target['enabled'] = !value);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _move(int index, int delta) async {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _targets.length) return;
    setState(() {
      final item = _targets.removeAt(index);
      _targets.insert(newIndex, item);
    });
    try {
      await _api.reorderShareTargets(_targets.map((t) => t['target_key'] as String).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reorder failed: $e')));
      _load();
    }
  }

  Future<void> _openEditor(Map<String, dynamic> target) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TargetEditorSheet(target: target),
    );
    if (result != null) {
      setState(() {
        final idx = _targets.indexWhere((t) => t['target_key'] == target['target_key']);
        if (idx != -1) _targets[idx] = {..._targets[idx], ...result};
      });
      try {
        await _api.updateShareTarget(target['target_key'], result);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
        _load();
      }
    }
  }

  Future<void> _deleteCustomTarget(Map<String, dynamic> target) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this share target?'),
        content: Text('"${target['custom_label']}" will be removed for everyone on this account.'),
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
      await _api.deleteShareTarget(target['target_key']);
      _load();
    }
  }

  Future<void> _addCustomTarget() async {
    final labelCtrl = TextEditingController();
    final schemeCtrl = TextEditingController();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add share target', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: 'App / platform name', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: schemeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Package name or URL scheme (optional)',
                  hintText: 'e.g. com.linkedin.android',
                  border: OutlineInputBorder(),
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
    );

    if (result == true && labelCtrl.text.trim().isNotEmpty) {
      try {
        await _api.createShareTarget(
          customLabel: labelCtrl.text.trim(),
          packageOrScheme: schemeCtrl.text.trim().isEmpty ? null : schemeCtrl.text.trim(),
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
      appBar: AppBar(title: const Text('Share Targets')),
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
                      'Show, hide, reorder, and restyle the apps/platforms available when sharing flyers, logos, and creative assets. Changes apply for everyone on this account.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                  ..._targets.asMap().entries.map((entry) {
                    final index = entry.key;
                    final target = entry.value;
                    final key = target['target_key'] as String;
                    final label = target['custom_label'] ?? kShareTargetDefaultLabels[key] ?? key;
                    final iconKey = target['icon_override'] ?? kShareTargetDefaultIcons[key] ?? 'share_outlined';
                    final icon = kShareTargetIconOptions[iconKey] ?? Icons.share_outlined;
                    final colorHex = target['color_override'] as String?;
                    final color = colorHex != null ? _hexToColor(colorHex) : Theme.of(context).colorScheme.primary;
                    final enabled = target['enabled'] as bool? ?? true;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(icon, color: enabled ? color : Colors.grey),
                        title: Text(label, style: TextStyle(color: enabled ? null : Colors.grey)),
                        subtitle: target['is_custom'] == true ? const Text('Custom target', style: TextStyle(fontSize: 11)) : null,
                        onTap: () => _openEditor(target),
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
                              onPressed: index == _targets.length - 1 ? null : () => _move(index, 1),
                              tooltip: 'Move down',
                            ),
                            Switch(value: enabled, onChanged: (v) => _toggleEnabled(target, v)),
                            if (target['is_custom'] == true)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                tooltip: 'Delete',
                                onPressed: () => _deleteCustomTarget(target),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add share target'),
                    onPressed: _addCustomTarget,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

Color _hexToColor(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

class _TargetEditorSheet extends StatefulWidget {
  final Map<String, dynamic> target;
  const _TargetEditorSheet({required this.target});

  @override
  State<_TargetEditorSheet> createState() => _TargetEditorSheetState();
}

class _TargetEditorSheetState extends State<_TargetEditorSheet> {
  late TextEditingController _labelCtrl;
  late TextEditingController _schemeCtrl;
  late String _iconKey;
  late Color _color;

  @override
  void initState() {
    super.initState();
    final key = widget.target['target_key'] as String;
    _labelCtrl = TextEditingController(text: widget.target['custom_label'] ?? kShareTargetDefaultLabels[key] ?? key);
    _schemeCtrl = TextEditingController(text: widget.target['custom_package_or_scheme'] ?? '');
    _iconKey = widget.target['icon_override'] ?? kShareTargetDefaultIcons[key] ?? 'share_outlined';
    final colorHex = widget.target['color_override'] as String?;
    _color = colorHex != null ? _hexToColor(colorHex) : Colors.deepPurple;
  }

  String _colorToHex(Color c) {
    final v = c.value & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }

  Future<void> _pickColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initial: _color, title: 'Target color'),
    );
    if (picked != null) setState(() => _color = picked);
  }

  void _save() {
    Navigator.pop(context, {
      'custom_label': _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
      'icon_override': _iconKey,
      'color_override': _colorToHex(_color),
      'custom_package_or_scheme': _schemeCtrl.text.trim().isEmpty ? null : _schemeCtrl.text.trim(),
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
            Text('Customize share target', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(labelText: 'Label', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _schemeCtrl,
              decoration: const InputDecoration(labelText: 'Package name / URL scheme', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 16),
            const Text('Icon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: kShareTargetIconOptions.entries.map((e) {
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
