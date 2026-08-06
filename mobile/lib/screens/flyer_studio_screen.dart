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
import '../services/api_service.dart';

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
  String? _selectedTemplateId;

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
      final templates = await _api.getFlyerTemplates();
      setState(() {
        _templates = templates;
        _selectedTemplateId = templates.isNotEmpty ? templates.first['id'] : null;
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
      body: _loadingTemplates
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _generating ? null : _quickGenerate,
                        icon: const Icon(Icons.bolt),
                        label: Text(widget.leadId != null ? 'Quick Generate (AI, this lead)' : 'Quick Generate (AI)'),
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
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save Flyer'),
                  ),
                ],

                if (_savedImageUrl != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.green.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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
                  ),
                ],
              ],
            ),
    );
  }
}
