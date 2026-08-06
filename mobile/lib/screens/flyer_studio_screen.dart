// lib/screens/flyer_studio_screen.dart
//
// Flyer Studio — Phase 5. Two modes:
//   - Quick Generate (AI): one tap, Gemini writes the copy grounded in
//     the lead's real context (if opened from a lead), flyer renders instantly.
//   - Manual: counselor fills each field themselves.
// Either way: preview -> optionally edit fields -> Save -> get a real
// shareable image URL -> optional "Open in Canva to polish" (manual
// upload — Canva's Autofill API needs Enterprise, not used here).

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import '../services/api_service.dart';
import '../widgets/glass_widgets.dart';

class FlyerStudioScreen extends StatefulWidget {
  final String? leadId; // optional — enables AI grounding + "Save to this lead"
  const FlyerStudioScreen({super.key, this.leadId});

  @override
  State<FlyerStudioScreen> createState() => _FlyerStudioScreenState();
}

class _FlyerStudioScreenState extends State<FlyerStudioScreen> {
  final ApiService _api = ApiService();

  bool _loadingTemplates = true;
  List<Map<String, dynamic>> _templates = [];
  List<String> _availableFonts = [];
  String? _selectedTemplateId;
  String _selectedFont = 'Space Grotesk';
  Color _selectedAccentColor = const Color(0xFFE63946);
  final List<Color> _accentColorSwatches = const [
    Color(0xFFE63946), // red
    Color(0xFFFFD60A), // gold
    Color(0xFF06D6A0), // teal-green
    Color(0xFF118AB2), // blue
    Color(0xFFEF476F), // pink
    Color(0xFFFFFFFF), // white
  ];

  bool _generating = false;
  String? _error;
  String? _imageDataUri;
  Map<String, dynamic> _fields = {};
  bool _aiGenerated = false;

  bool _saving = false;
  String? _savedImageUrl;

  final Map<String, TextEditingController> _fieldControllers = {};

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    try {
      final result = await _api.getFlyerTemplates();
      final templates = (result['templates'] as List).cast<Map<String, dynamic>>();
      final fonts = (result['available_fonts'] as List).cast<String>();
      setState(() {
        _templates = templates;
        _availableFonts = fonts;
        _selectedTemplateId = templates.isNotEmpty ? templates.first['id'] : null;
        _selectedFont = fonts.isNotEmpty ? fonts.first : 'Space Grotesk';
        _loadingTemplates = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingTemplates = false;
      });
    }
  }

  void _syncControllers() {
    _fieldControllers.clear();
    _fields.forEach((key, value) {
      _fieldControllers[key] = TextEditingController(text: value?.toString() ?? '');
    });
  }

  String _colorToHex(Color c) => '#${c.value.toRadixString(16).substring(2).padLeft(6, '0')}';

  Future<void> _quickGenerate() async {
    if (_selectedTemplateId == null) return;
    setState(() {
      _generating = true;
      _error = null;
      _savedImageUrl = null;
    });
    try {
      final result = await _api.quickGenerateFlyer(templateId: _selectedTemplateId!, leadId: widget.leadId);
      setState(() {
        _imageDataUri = result['image_data_uri'];
        _fields = Map<String, dynamic>.from(result['fields']);
        _fields['font_family'] = _selectedFont;
        _fields['accent_color'] = _colorToHex(_selectedAccentColor);
        _aiGenerated = true;
        _syncControllers();
        _generating = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _generating = false;
      });
    }
  }

  Future<void> _regenerateFromFields() async {
    if (_selectedTemplateId == null) return;
    final updatedFields = <String, dynamic>{};
    _fieldControllers.forEach((key, ctrl) => updatedFields[key] = ctrl.text);
    updatedFields['font_family'] = _selectedFont;
    updatedFields['accent_color'] = _colorToHex(_selectedAccentColor);

    setState(() {
      _generating = true;
      _error = null;
      _savedImageUrl = null;
    });
    try {
      final result = await _api.generateFlyer(templateId: _selectedTemplateId!, fields: updatedFields);
      setState(() {
        _imageDataUri = result['image_data_uri'];
        _fields = updatedFields;
        _generating = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _generating = false;
      });
    }
  }

  void _startManualFill() {
    final template = _templates.firstWhere((t) => t['id'] == _selectedTemplateId);
    final fields = <String, dynamic>{};
    for (final f in (template['fields'] as List)) {
      if (f == 'font_family' || f == 'accent_color') continue; // controlled by dedicated pickers, not a text field
      fields[f] = '';
    }
    setState(() {
      _fields = fields;
      _aiGenerated = false;
      _imageDataUri = null;
      _syncControllers();
    });
  }

  Future<void> _save() async {
    if (_selectedTemplateId == null) return;
    setState(() => _saving = true);
    try {
      final updatedFields = <String, dynamic>{};
      _fieldControllers.forEach((key, ctrl) => updatedFields[key] = ctrl.text);
      updatedFields['font_family'] = _selectedFont;
      updatedFields['accent_color'] = _colorToHex(_selectedAccentColor);
      final result = await _api.saveFlyer(
        templateId: _selectedTemplateId!,
        fields: updatedFields,
        leadId: widget.leadId,
        aiGenerated: _aiGenerated,
      );
      setState(() {
        _savedImageUrl = result['image_url'];
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  Future<void> _shareImage() async {
    if (_imageDataUri == null) return;
    try {
      final bytes = base64Decode(_imageDataUri!.split(',').last);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/flyer_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      // Opens the native Android share sheet — the counselor picks WhatsApp
      // (or any app) themselves and confirms the send there. This actually
      // attaches the image (unlike a wa.me link, which can only pre-fill
      // text) while staying within the same manual-confirm safety pattern
      // used everywhere else in Cockpit's WhatsApp flow.
      await Share.shareXFiles([XFile(file.path)], text: _fieldControllers['contact_line']?.text ?? '');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share: $e')));
      }
    }
  }

  Future<void> _openInCanva() async {
    // Canva's Autofill API requires Canva Enterprise ($15k-50k+/year) —
    // not used here. This opens Canva's site so the counselor can
    // manually upload the saved flyer image for further polish on their
    // own free/Pro account instead.
    await launchUrl(Uri.parse('https://www.canva.com/create/flyers/'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flyer Studio')),
      body: GlassBackdrop(
        child: _loadingTemplates
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedTemplateId,
                  decoration: const InputDecoration(labelText: 'Template', border: OutlineInputBorder()),
                  items: _templates.map((t) => DropdownMenuItem(value: t['id'] as String, child: Text(t['name']))).toList(),
                  onChanged: (v) => setState(() {
                    _selectedTemplateId = v;
                    _imageDataUri = null;
                    _savedImageUrl = null;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _availableFonts.contains(_selectedFont) ? _selectedFont : null,
                  decoration: const InputDecoration(labelText: 'Font', border: OutlineInputBorder()),
                  items: _availableFonts.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  onChanged: (v) => setState(() => _selectedFont = v ?? _selectedFont),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Accent color:', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 12),
                    ..._accentColorSwatches.map((c) => GestureDetector(
                          onTap: () => setState(() => _selectedAccentColor = c),
                          child: Container(
                            width: 30,
                            height: 30,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _selectedAccentColor.value == c.value ? Colors.black : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                        )),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        onPressed: _generating ? null : _quickGenerate,
                        icon: Icons.bolt,
                        child: Text(widget.leadId != null ? 'Quick Generate (AI, this lead)' : 'Quick Generate (AI)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _startManualFill, child: const Text('Fill Manually Instead')),
                if (_generating) const Padding(padding: EdgeInsets.only(top: 20), child: Center(child: CircularProgressIndicator())),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),

                if (_fieldControllers.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Edit text', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._fieldControllers.entries
                      .where((e) => e.key != 'org_name' && e.key != 'theme_color')
                      .map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TextField(
                              controller: e.value,
                              decoration: InputDecoration(labelText: e.key.replaceAll('_', ' '), isDense: true, border: const OutlineInputBorder()),
                            ),
                          )),
                  OutlinedButton(onPressed: _generating ? null : _regenerateFromFields, child: const Text('Preview with these edits')),
                ],

                if (_imageDataUri != null) ...[
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      Uri.parse(_imageDataUri!).data!.contentAsBytes(),
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GlassButton(
                          onPressed: _saving ? null : _save,
                          icon: Icons.save,
                          child: Text(_saving ? 'Saving...' : 'Save Flyer'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _shareImage,
                          icon: const Icon(Icons.share),
                          label: const Text('Share to WhatsApp'),
                        ),
                      ),
                    ],
                  ),
                ],

                if (_savedImageUrl != null) ...[
                  const SizedBox(height: 16),
                  GlassContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Saved! Shareable link:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        SelectableText(_savedImageUrl!, style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _openInCanva,
                          icon: const Icon(Icons.brush),
                          label: const Text('Open Canva to Polish (manual upload)'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
      ),
    );
  }
}
