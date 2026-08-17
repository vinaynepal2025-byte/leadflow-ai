import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/color_picker_dialog.dart';

// Must stay in sync with backend/services/fontSetup.js's AVAILABLE_FONTS --
// same reasoning as flyer_studio's own font picker: these are the fonts
// actually bundled and registered on the server, so offering anything
// else here would silently fail server-side validation.
const List<String> kLogoFontOptions = [
  'Space Grotesk',
  'Playfair Display',
  'Poppins',
  'Lato',
  'Montserrat',
  'Open Sans',
];

const Map<String, String> kIconShapeLabels = {
  'circle': 'Circle',
  'square': 'Square',
  'diamond': 'Diamond',
  'hexagon': 'Hexagon',
  'star': 'Star',
  'shield': 'Shield',
};

class GenerateLogoScreen extends StatefulWidget {
  const GenerateLogoScreen({super.key});

  @override
  State<GenerateLogoScreen> createState() => _GenerateLogoScreenState();
}

class _GenerateLogoScreenState extends State<GenerateLogoScreen> {
  final _api = ApiService();

  List<Map<String, dynamic>> _templates = [];
  bool _loadingTemplates = true;
  String _templateId = 'monogram_badge';

  final _brandNameCtrl = TextEditingController();
  final _initialsCtrl = TextEditingController();
  Color _primaryColor = const Color(0xFF1B2A4A);
  Color _accentColor = const Color(0xFFE8A33D);
  String _fontFamily = kLogoFontOptions.first;
  String _iconShape = 'circle';

  String? _previewDataUri;
  bool _generating = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _brandNameCtrl.dispose();
    _initialsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    try {
      final templates = await _api.getLogoTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _loadingTemplates = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = 'Could not load templates: $e';
        _loadingTemplates = false;
      });
    }
  }

  /// The selected template's declared field list, straight from the
  /// backend (routes/tenantLogos.js's GET /templates) -- driving which
  /// optional inputs (initials, icon shape) this screen shows off of
  /// this instead of a hardcoded per-template-id switch means a new
  /// template that declares 'initials' or 'icon_shape' in its own
  /// fields array automatically gets the matching input here with zero
  /// Flutter changes, the same way it already gets picked up by the
  /// template chooser above with zero changes.
  List<String> get _currentTemplateFields {
    final match = _templates.where((t) => t['id'] == _templateId).toList();
    if (match.isEmpty) return const [];
    return (match.first['fields'] as List?)?.cast<String>() ?? const [];
  }

  Map<String, dynamic> _buildFields() {
    final fields = <String, dynamic>{
      'brand_name': _brandNameCtrl.text.trim().isEmpty ? 'Brand Name' : _brandNameCtrl.text.trim(),
      'primary_color': _colorToHex(_primaryColor),
      'accent_color': _colorToHex(_accentColor),
      'font_family': _fontFamily,
    };
    if (_currentTemplateFields.contains('initials') && _initialsCtrl.text.trim().isNotEmpty) {
      fields['initials'] = _initialsCtrl.text.trim();
    }
    if (_currentTemplateFields.contains('icon_shape')) {
      fields['icon_shape'] = _iconShape;
    }
    return fields;
  }

  Future<void> _generatePreview() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final dataUri = await _api.generateLogo(templateId: _templateId, fields: _buildFields());
      if (mounted) setState(() => _previewDataUri = dataUri);
    } catch (e) {
      if (mounted) setState(() => _error = 'Generation failed: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _saveToLibrary() async {
    if (_previewDataUri == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final base64Data = _previewDataUri!.split(',').last;
      final bytes = base64Decode(base64Data);
      final dir = await getTemporaryDirectory();
      final tempPath = '${dir.path}/generated_logo_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(tempPath).writeAsBytes(bytes);

      await _api.uploadTenantLogo(
        filePath: tempPath,
        label: _brandNameCtrl.text.trim().isEmpty ? 'Generated Logo' : _brandNameCtrl.text.trim(),
        isDefault: false,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickColor({required bool isPrimary}) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(
        initial: isPrimary ? _primaryColor : _accentColor,
        title: isPrimary ? 'Primary color' : 'Accent color',
      ),
    );
    if (picked != null) {
      setState(() {
        if (isPrimary) {
          _primaryColor = picked;
        } else {
          _accentColor = picked;
        }
      });
    }
  }

  String _colorToHex(Color c) {
    final v = c.value & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }

  Widget _colorSwatch({required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)),
            ),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generate Logo')),
      body: _loadingTemplates
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Template', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _templates.map((t) {
                      final id = t['id'] as String;
                      final selected = id == _templateId;
                      return ChoiceChip(
                        label: Text(t['name'] as String),
                        selected: selected,
                        onSelected: (_) => setState(() {
                          _templateId = id;
                          _previewDataUri = null;
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _brandNameCtrl,
                    decoration: const InputDecoration(labelText: 'Brand name', border: OutlineInputBorder(), isDense: true),
                  ),
                  if (_currentTemplateFields.contains('initials')) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _initialsCtrl,
                      maxLength: 3,
                      decoration: const InputDecoration(labelText: 'Initials (optional)', hintText: 'Auto-derived if left blank', border: OutlineInputBorder(), isDense: true),
                    ),
                  ],
                  if (_currentTemplateFields.contains('icon_shape')) ...[
                    const SizedBox(height: 16),
                    const Text('Icon shape', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: kIconShapeLabels.entries.map((e) => ButtonSegment(value: e.key, label: Text(e.value))).toList(),
                      selected: {_iconShape},
                      onSelectionChanged: (s) => setState(() => _iconShape = s.first),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _colorSwatch(label: 'Primary color', color: _primaryColor, onTap: () => _pickColor(isPrimary: true)),
                  _colorSwatch(label: 'Accent color', color: _accentColor, onTap: () => _pickColor(isPrimary: false)),
                  const SizedBox(height: 16),
                  const Text('Font', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _fontFamily,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: kLogoFontOptions.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                    onChanged: (v) => setState(() => _fontFamily = v ?? _fontFamily),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    icon: _generating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome),
                    label: Text(_previewDataUri == null ? 'Generate Preview' : 'Regenerate Preview'),
                    onPressed: _generating ? null : _generatePreview,
                  ),
                  if (_previewDataUri != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.shade50,
                      ),
                      child: Center(
                        child: Image.memory(
                          base64Decode(_previewDataUri!.split(',').last),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check),
                      label: const Text('Save to Library'),
                      onPressed: _saving ? null : _saveToLibrary,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
            ),
    );
  }
}
