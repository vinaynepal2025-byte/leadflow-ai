import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/color_picker_dialog.dart';
import 'more_screen.dart' show kMoreMenuIconOptions, kMoreMenuDefaults;
import '../widgets/styled_icon_badge.dart';

class CustomizeMoreMenuScreen extends StatefulWidget {
  // Set when arriving from Settings Studio's search -- opens that one
  // item's editor sheet automatically as soon as the list loads, so
  // "search for a button, land straight on its style editor" is a real
  // one-tap jump rather than "land on the right screen, then still have
  // to find and tap the row yourself."
  final String? initialEditKey;
  const CustomizeMoreMenuScreen({super.key, this.initialEditKey});

  @override
  State<CustomizeMoreMenuScreen> createState() => _CustomizeMoreMenuScreenState();
}

class _CustomizeMoreMenuScreenState extends State<CustomizeMoreMenuScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _api.getMoreMenuItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
    if (widget.initialEditKey != null) {
      for (final item in _items) {
        if (item['item_key'] == widget.initialEditKey) {
          _openEditor(item);
          break;
        }
      }
    }
  }

  Future<void> _toggleEnabled(Map<String, dynamic> item, bool value) async {
    setState(() => item['enabled'] = value);
    try {
      await _api.updateMoreMenuItem(item['item_key'], {'enabled': value});
    } catch (e) {
      setState(() => item['enabled'] = !value);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _move(int index, int delta) async {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _items.length) return;
    setState(() {
      final item = _items.removeAt(index);
      _items.insert(newIndex, item);
    });
    try {
      await _api.reorderMoreMenuItems(_items.map((i) => i['item_key'] as String).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reorder failed: $e')));
      _load();
    }
  }

  Future<void> _openEditor(Map<String, dynamic> item) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemEditorSheet(item: item),
    );
    if (result != null) {
      setState(() {
        final idx = _items.indexWhere((i) => i['item_key'] == item['item_key']);
        if (idx != -1) _items[idx] = {..._items[idx], ...result};
      });
      try {
        await _api.updateMoreMenuItem(item['item_key'], result);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
        _load();
      }
    }
  }

  Future<void> _deleteCustomItem(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this item?'),
        content: Text('"${item['custom_label']}" will be removed for everyone on this account.'),
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
      await _api.deleteMoreMenuItem(item['item_key']);
      _load();
    }
  }

  Future<void> _addCustomItem() async {
    final labelCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

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
              Text('Add custom link', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: 'Label', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'URL (https://...)', border: OutlineInputBorder(), isDense: true),
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

    if (result == true && labelCtrl.text.trim().isNotEmpty && urlCtrl.text.trim().isNotEmpty) {
      try {
        await _api.createMoreMenuItem(
          customLabel: labelCtrl.text.trim(),
          actionValue: urlCtrl.text.trim(),
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
      appBar: AppBar(title: const Text('Customize More Menu')),
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
                      'Show, hide, reorder, and restyle every item on the More menu.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                  ..._items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final key = item['item_key'] as String;
                    final def = kMoreMenuDefaults[key];
                    final label = item['custom_label'] ?? def?.label ?? key;
                    final iconKey = item['icon_override'] ?? def?.icon ?? 'star';
                    final icon = kMoreMenuIconOptions[iconKey] ?? Icons.star;
                    final colorHex = item['color_override'] as String?;
                    final color = colorHex != null ? _hexToColor(colorHex) : Theme.of(context).colorScheme.primary;
                    final enabled = item['enabled'] as bool? ?? true;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(icon, color: enabled ? color : Colors.grey),
                        title: Text(label, style: TextStyle(color: enabled ? null : Colors.grey)),
                        subtitle: item['is_custom'] == true ? const Text('Custom link', style: TextStyle(fontSize: 11)) : null,
                        onTap: () => _openEditor(item),
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
                              onPressed: index == _items.length - 1 ? null : () => _move(index, 1),
                              tooltip: 'Move down',
                            ),
                            Switch(value: enabled, onChanged: (v) => _toggleEnabled(item, v)),
                            if (item['is_custom'] == true)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                tooltip: 'Delete',
                                onPressed: () => _deleteCustomItem(item),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add custom link'),
                    onPressed: _addCustomItem,
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

class _ItemEditorSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  const _ItemEditorSheet({required this.item});

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  late TextEditingController _labelCtrl;
  late String _iconKey;
  late Color _color;
  late String _styleVariant;
  Color? _gradientEnd;

  @override
  void initState() {
    super.initState();
    final key = widget.item['item_key'] as String;
    final def = kMoreMenuDefaults[key];
    _labelCtrl = TextEditingController(text: widget.item['custom_label'] ?? def?.label ?? key);
    _iconKey = widget.item['icon_override'] ?? def?.icon ?? 'star';
    final colorHex = widget.item['color_override'] as String?;
    _color = colorHex != null ? _hexToColor(colorHex) : Colors.deepPurple;
    _styleVariant = widget.item['style_variant'] as String? ?? 'flat';
    final gradHex = widget.item['gradient_override'] as String?;
    _gradientEnd = gradHex != null ? _hexToColor(gradHex) : null;
  }

  String _colorToHex(Color c) {
    final v = c.value & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }

  Future<void> _pickColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initial: _color, title: 'Item color'),
    );
    if (picked != null) setState(() => _color = picked);
  }

  void _save() {
    Navigator.pop(context, {
      'custom_label': _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
      'icon_override': _iconKey,
      'color_override': _colorToHex(_color),
      'style_variant': _styleVariant,
      'gradient_override': _styleVariant == 'gradient_badge' ? _colorToHex(_gradientEnd ?? _color) : null,
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
            Text('Customize item', style: Theme.of(context).textTheme.titleMedium),
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
              children: kMoreMenuIconOptions.entries.map((e) {
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
            const Text('Style', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: kStyleVariantLabels.entries.map((e) {
                final selected = e.key == _styleVariant;
                return ChoiceChip(
                  label: Text(e.value),
                  selected: selected,
                  onSelected: (_) => setState(() => _styleVariant = e.key),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Center(
              child: styledIconBadge(
                icon: kMoreMenuIconOptions[_iconKey] ?? Icons.star,
                color: _color,
                gradientEnd: _gradientEnd,
                styleVariant: _styleVariant,
                size: 56,
              ),
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
            if (_styleVariant == 'gradient_badge') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Gradient End', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDialog<Color>(
                        context: context,
                        builder: (_) => ColorPickerDialog(initial: _gradientEnd ?? _color, title: 'Gradient end colour'),
                      );
                      if (picked != null) setState(() => _gradientEnd = picked);
                    },
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: _gradientEnd ?? _color, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)),
                    ),
                  ),
                ],
              ),
            ],
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
