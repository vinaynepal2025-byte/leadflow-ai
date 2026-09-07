// lib/screens/exam_template_editor_screen.dart
//
// Exam Intelligence — report card template customization, with a real
// (backend-rendered, WYSIWYG) live preview rather than a Flutter-side mock.
// The preview calls POST /exams/templates/preview on every change (debounced)
// so the counselor sees the actual fonts/layout/logo placement before ever
// trusting it enough to send to a parent.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../widgets/glass_widgets.dart';
import '../widgets/color_picker_dialog.dart';

class ExamTemplateEditorScreen extends StatefulWidget {
  const ExamTemplateEditorScreen({super.key});

  @override
  State<ExamTemplateEditorScreen> createState() => _ExamTemplateEditorScreenState();
}

class _ExamTemplateEditorScreenState extends State<ExamTemplateEditorScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  String? _templateId;

  final _titleController = TextEditingController();
  final _footerController = TextEditingController();
  final _disclaimerController = TextEditingController();
  Color _headerColor = const Color(0xFF1E3A8A);
  String? _logoUrl;
  List<Map<String, dynamic>> _logos = [];
  final Set<String> _fields = {'subjects', 'total', 'rank', 'batchAverage', 'previousDelta', 'narrative'};

  Uint8List? _previewBytes;
  bool _previewLoading = false;
  Timer? _debounce;

  static const _allFields = [
    ('subjects', 'Subjects table'),
    ('total', 'Total & grade bar'),
    ('rank', 'Rank'),
    ('batchAverage', 'Batch average'),
    ('previousDelta', 'Change vs previous exam'),
    ('narrative', 'Narrative / remark'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _footerController.dispose();
    _disclaimerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final templates = await _api.getExamReportTemplates();
      final logos = await _api.getTenantLogos();
      final Map<String, dynamic> def = templates.isEmpty
          ? {}
          : templates.firstWhere((t) => t['is_default'] == true, orElse: () => templates.first);
      final config = (def['config'] as Map?)?.cast<String, dynamic>() ?? {};
      final branding = (config['branding'] as Map?)?.cast<String, dynamic>() ?? {};
      final fieldsList = (config['fields'] as List?)?.cast<String>();

      setState(() {
        _templateId = def['id'] as String?;
        _titleController.text = branding['title']?.toString() ?? '';
        _footerController.text = config['footerText']?.toString() ?? '';
        _disclaimerController.text = config['disclaimer']?.toString() ?? '';
        _headerColor = _parseColor(branding['headerColor']?.toString()) ?? const Color(0xFF1E3A8A);
        _logoUrl = branding['logoUrl']?.toString();
        _logos = logos;
        if (fieldsList != null) {
          _fields
            ..clear()
            ..addAll(fieldsList);
        }
        _loading = false;
      });
      _refreshPreview();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.replaceAll('#', '');
    final value = int.tryParse(clean, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  String _toHex(Color c) {
    String ch(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${ch(((c.r * 255.0).round()) & 0xff)}${ch(((c.g * 255.0).round()) & 0xff)}${ch(((c.b * 255.0).round()) & 0xff)}';
  }

  Map<String, dynamic> _buildConfig() {
    return {
      'fields': _fields.toList(),
      'subjectOrder': null,
      'branding': {
        'headerColor': _toHex(_headerColor),
        'title': _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
        'logoUrl': _logoUrl,
      },
      'footerText': _footerController.text.trim().isEmpty ? null : _footerController.text.trim(),
      'disclaimer': _disclaimerController.text.trim().isEmpty ? null : _disclaimerController.text.trim(),
    };
  }

  void _scheduleRefreshPreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _refreshPreview);
  }

  Future<void> _refreshPreview() async {
    setState(() => _previewLoading = true);
    try {
      final bytes = await _api.previewExamReportCard(_buildConfig());
      if (mounted) {
        setState(() {
          _previewBytes = bytes;
          _previewLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  Future<void> _pickColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initial: _headerColor, title: 'Header color'),
    );
    if (picked != null) {
      setState(() => _headerColor = picked);
      _scheduleRefreshPreview();
    }
  }

  Future<void> _pickLogo() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.block), title: const Text('No logo'), onTap: () => Navigator.pop(ctx, '')),
            ..._logos.map((l) => ListTile(
                  leading: Image.network(
                    l['image_url']?.toString() ?? '',
                    width: 40,
                    height: 40,
                    errorBuilder: (_, __, ___) => const Icon(Icons.image),
                  ),
                  title: Text(l['label']?.toString() ?? 'Logo'),
                  onTap: () => Navigator.pop(ctx, l['image_url']?.toString() ?? ''),
                )),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate),
              title: const Text('Upload new logo'),
              onTap: () => Navigator.pop(ctx, '__upload__'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == '__upload__') {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (picked == null) return;
      try {
        final uploaded = await _api.uploadTenantLogo(filePath: picked.path, label: 'Report card logo');
        setState(() {
          _logos = [..._logos, uploaded];
          _logoUrl = uploaded['image_url'] as String?;
        });
        _scheduleRefreshPreview();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
      return;
    }
    setState(() => _logoUrl = choice.isEmpty ? null : choice);
    _scheduleRefreshPreview();
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final config = _buildConfig();
      if (_templateId == null) {
        final created = await _api.createExamReportTemplate('Default', config);
        _templateId = created['id'] as String?;
      } else {
        await _api.updateExamReportTemplate(_templateId!, config: config);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customize Report Card')),
      body: GlassBackdrop(
        child: _loading && _previewBytes == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _previewCard(),
                      const SizedBox(height: 16),
                      _formCard(),
                      const SizedBox(height: 16),
                      GlassButton(onPressed: _loading ? null : _save, icon: Icons.save, child: const Text('Save template')),
                      const SizedBox(height: 24),
                    ],
                  ),
      ),
    );
  }

  Widget _previewCard() {
    return GlassContainer(
      child: Column(
        children: [
          const Align(alignment: Alignment.centerLeft, child: Text('Live preview', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(height: 8),
          if (_previewBytes != null)
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_previewBytes!, fit: BoxFit.contain))
          else
            const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
          if (_previewLoading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        ],
      ),
    );
  }

  Widget _formCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Template', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: "Header title override (blank = student's own college)"),
            onChanged: (_) => _scheduleRefreshPreview(),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Header color'),
            trailing: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: _headerColor, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)),
            ),
            onTap: _pickColor,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Logo'),
            subtitle: Text(_logoUrl == null ? 'None' : 'Selected'),
            trailing: _logoUrl != null
                ? Image.network(_logoUrl!, width: 32, height: 32, errorBuilder: (_, __, ___) => const Icon(Icons.image))
                : const Icon(Icons.add_photo_alternate),
            onTap: _pickLogo,
          ),
          const Divider(height: 24),
          const Text('Sections to show', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._allFields.map((f) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(f.$2),
                value: _fields.contains(f.$1),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _fields.add(f.$1);
                    } else {
                      _fields.remove(f.$1);
                    }
                  });
                  _scheduleRefreshPreview();
                },
              )),
          const Divider(height: 24),
          TextField(
            controller: _footerController,
            decoration: const InputDecoration(labelText: 'Footer text (optional)'),
            onChanged: (_) => _scheduleRefreshPreview(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _disclaimerController,
            decoration: const InputDecoration(labelText: 'Disclaimer'),
            onChanged: (_) => _scheduleRefreshPreview(),
          ),
        ],
      ),
    );
  }
}
