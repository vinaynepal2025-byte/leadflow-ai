import 'package:flutter/material.dart';
import '../screens/customize_registry.dart';
import '../services/api_service.dart';
import 'color_picker_dialog.dart';
import 'styled_icon_badge.dart';

Color _hexToColor(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

String _colorToHex(Color c) {
  final v = c.value & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0')}';
}

/// The live design-mode editor: opened by tapping any tile while Edit
/// Mode is on, right where that tile already lives (More screen, and
/// wherever else opts in), instead of navigating to a separate
/// "Customize X" screen. Same colour/style-variant/gradient fields
/// every Customize* screen's own per-item editor already persists --
/// this is a second, in-place entry point onto the exact same backend
/// data, not a parallel styling system.
///
/// Returns the applied {color, styleVariant, gradientEnd} on save (null
/// on cancel) so the caller can update its own local tile state
/// immediately, without waiting on a re-fetch, for a genuinely "live"
/// feel.
class QuickStyleEditorSheet extends StatefulWidget {
  final CustomizeRegistryItem item;
  final String currentColorHex;
  final String currentStyleVariant;
  final String? currentGradientEndHex;

  const QuickStyleEditorSheet({
    super.key,
    required this.item,
    required this.currentColorHex,
    this.currentStyleVariant = 'flat',
    this.currentGradientEndHex,
  });

  @override
  State<QuickStyleEditorSheet> createState() => _QuickStyleEditorSheetState();
}

class _QuickStyleEditorSheetState extends State<QuickStyleEditorSheet> {
  final _api = ApiService();
  late Color _color;
  late String _styleVariant;
  Color? _gradientEnd;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _color = _hexToColor(widget.currentColorHex);
    _styleVariant = widget.currentStyleVariant;
    _gradientEnd = widget.currentGradientEndHex != null ? _hexToColor(widget.currentGradientEndHex!) : null;
  }

  Future<void> _pickColor({required bool isGradientEnd}) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(
        initial: isGradientEnd ? (_gradientEnd ?? _color) : _color,
        title: isGradientEnd ? 'Gradient end colour' : 'Colour',
      ),
    );
    if (picked != null) {
      setState(() {
        if (isGradientEnd) {
          _gradientEnd = picked;
        } else {
          _color = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final colorHex = _colorToHex(_color);
    final gradientHex = _styleVariant == 'gradient_badge' ? _colorToHex(_gradientEnd ?? _color) : null;
    try {
      await widget.item.applyStyle(_api, colorHex: colorHex, styleVariant: _styleVariant, gradientEndHex: gradientHex);
      if (mounted) {
        Navigator.pop(context, {
          'color': colorHex,
          'styleVariant': _styleVariant,
          'gradientEnd': gradientHex,
        });
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.edit, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.item.label, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            Text(widget.item.category, style: TextStyle(fontSize: 11, color: widget.item.categoryColor)),
            const SizedBox(height: 16),
            Center(
              child: styledIconBadge(
                icon: widget.item.icon,
                color: _color,
                gradientEnd: _gradientEnd,
                styleVariant: _styleVariant,
                size: 56,
              ),
            ),
            const SizedBox(height: 20),
            const Text('Style', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kStyleVariantLabels.entries.map((e) {
                final selected = e.key == _styleVariant;
                return ChoiceChip(
                  label: Text(e.value),
                  selected: selected,
                  onSelected: (_) => setState(() => _styleVariant = e.key),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Colour', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _pickColor(isGradientEnd: false),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: _color, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)),
                  ),
                ),
              ],
            ),
            if (_styleVariant == 'gradient_badge') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Gradient end', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _pickColor(isGradientEnd: true),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: _gradientEnd ?? _color, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)),
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
