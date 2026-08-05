// lib/screens/excel_import_export_screen.dart
//
// Phase 2 — Customizable Excel/CSV Import & Export.
//
// Import flow: pick file -> preview (headers + sample rows + a best-guess
// mapping) -> counselor confirms/adjusts the mapping per column -> commit.
// Export flow: pick which columns to include (standard + any custom
// fields already defined for this tenant) -> opens a browser download.

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../widgets/glass_widgets.dart';

const List<String> _standardTargets = [
  'full_name', 'phone', 'email', 'source', 'notes', 'stage', 'parent_name', 'parent_phone',
];

class ExcelImportExportScreen extends StatefulWidget {
  const ExcelImportExportScreen({super.key});

  @override
  State<ExcelImportExportScreen> createState() => _ExcelImportExportScreenState();
}

class _ExcelImportExportScreenState extends State<ExcelImportExportScreen> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import / Export Leads'),
        bottom: TabBar(controller: _tab, tabs: const [Tab(text: 'Import'), Tab(text: 'Export')]),
      ),
      body: GlassBackdrop(
        child: TabBarView(
          controller: _tab,
          children: [_ImportTab(api: _api), _ExportTab(api: _api)],
        ),
      ),
    );
  }
}

// =======================================================================
// IMPORT TAB
// =======================================================================
class _ImportTab extends StatefulWidget {
  final ApiService api;
  const _ImportTab({required this.api});

  @override
  State<_ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends State<_ImportTab> {
  String? _filePath;
  String? _fileName;
  bool _loading = false;
  String? _error;

  Map<String, dynamic>? _preview; // headers, sample_rows, suggested_mapping
  final Map<String, String> _mapping = {}; // header -> target ('' = skip, 'custom:<key>' = custom)
  final Map<String, TextEditingController> _customKeyControllers = {};

  Map<String, dynamic>? _result; // commit result

  Future<void> _pickAndPreview() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
    );
    if (picked == null || picked.files.single.path == null) return;

    setState(() {
      _filePath = picked.files.single.path;
      _fileName = picked.files.single.name;
      _loading = true;
      _error = null;
      _preview = null;
      _result = null;
      _mapping.clear();
      _customKeyControllers.clear();
    });

    try {
      final preview = await widget.api.previewLeadsExcelImport(_filePath!, _fileName!);
      final suggested = (preview['suggested_mapping'] as Map).cast<String, dynamic>();
      setState(() {
        _preview = preview;
        for (final header in (preview['headers'] as List).cast<String>()) {
          _mapping[header] = suggested[header]?.toString() ?? '';
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _commit() async {
    if (_filePath == null || _fileName == null) return;
    // Resolve any "custom" selections to "custom:<key>" using the typed key.
    final finalMapping = <String, String>{};
    for (final entry in _mapping.entries) {
      if (entry.value == '__custom__') {
        final key = _customKeyControllers[entry.key]?.text.trim();
        if (key != null && key.isNotEmpty) finalMapping[entry.key] = 'custom:$key';
      } else if (entry.value.isNotEmpty) {
        finalMapping[entry.key] = entry.value;
      }
    }
    if (!finalMapping.containsValue('full_name')) {
      setState(() => _error = 'Map at least one column to "full_name" before importing');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.commitLeadsExcelImport(_filePath!, _fileName!, finalMapping);
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Works with any column layout — pick your file, then tell us which column is which.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              GlassButton(
                onPressed: _loading ? null : _pickAndPreview,
                icon: Icons.upload_file,
                child: Text(_fileName ?? 'Choose .xlsx or .csv file'),
              ),
            ],
          ),
        ),
        if (_loading) const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator())),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (_preview != null && _result == null) ...[
          const SizedBox(height: 16),
          Text('${_preview!['total_data_rows']} rows detected — map each column below', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...(_preview!['headers'] as List).cast<String>().map(_mappingRow),
          const SizedBox(height: 16),
          GlassButton(onPressed: _loading ? null : _commit, child: const Text('Import Leads')),
        ],
        if (_result != null) ...[
          const SizedBox(height: 20),
          GlassContainer(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_result!['created']} leads created', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${_result!['skipped_duplicate']} skipped (duplicate phone)'),
                  Text('${_result!['skipped_invalid']} skipped (missing name)'),
                ],
              ),
          ),
        ],
      ],
    );
  }

  Widget _mappingRow(String header) {
    final sampleIdx = (_preview!['headers'] as List).indexOf(header);
    final sampleRows = (_preview!['sample_rows'] as List).cast<List>();
    final sample = sampleRows.isNotEmpty && sampleIdx < sampleRows[0].length ? sampleRows[0][sampleIdx].toString() : '';

    final current = _mapping[header] ?? '';
    final isCustom = current == '__custom__' || (current.startsWith('custom:'));
    if (isCustom && !_customKeyControllers.containsKey(header)) {
      _customKeyControllers[header] = TextEditingController(
        text: current.startsWith('custom:') ? current.substring(7) : '',
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(header, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (sample.isNotEmpty) Text('e.g. "$sample"', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: isCustom
                ? TextField(
                    controller: _customKeyControllers[header],
                    decoration: const InputDecoration(labelText: 'Custom field key', isDense: true),
                    onChanged: (_) => setState(() {}),
                  )
                : DropdownButtonFormField<String>(
                    value: current.isEmpty ? '' : current,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('(skip this column)')),
                      ..._standardTargets.map((t) => DropdownMenuItem(value: t, child: Text(t))),
                      const DropdownMenuItem(value: '__custom__', child: Text('Custom field...')),
                    ],
                    onChanged: (v) => setState(() => _mapping[header] = v ?? ''),
                  ),
          ),
        ],
      ),
    );
  }
}

// =======================================================================
// EXPORT TAB
// =======================================================================
class _ExportTab extends StatefulWidget {
  final ApiService api;
  const _ExportTab({required this.api});

  @override
  State<_ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<_ExportTab> {
  final Set<String> _selected = {'full_name', 'phone', 'email', 'source', 'stage', 'notes'};
  List<Map<String, dynamic>> _customFields = [];
  bool _loadingFields = true;

  @override
  void initState() {
    super.initState();
    _loadCustomFields();
  }

  Future<void> _loadCustomFields() async {
    try {
      final fields = await widget.api.getCustomFieldDefinitions();
      if (mounted) setState(() {
        _customFields = fields;
        _loadingFields = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingFields = false);
    }
  }

  Future<void> _export() async {
    if (_selected.isEmpty) return;
    final url = widget.api.buildLeadsExportUrl(_selected.toList());
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingFields) return const Center(child: CircularProgressIndicator());

    final allColumns = [
      ..._standardTargets,
      'created_at',
      ..._customFields.map((f) => 'custom:${f['field_key']}'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Pick which columns to include — downloads as a .csv file, opens in Excel/Sheets.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        ...allColumns.map((col) {
          final label = col.startsWith('custom:')
              ? _customFields.firstWhere((f) => f['field_key'] == col.substring(7))['label'] ?? col
              : col;
          return CheckboxListTile(
            value: _selected.contains(col),
            title: Text(label),
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selected.add(col);
              } else {
                _selected.remove(col);
              }
            }),
          );
        }),
        const SizedBox(height: 16),
        GlassButton(
          onPressed: _selected.isEmpty ? null : _export,
          icon: Icons.download,
          child: const Text('Export as CSV'),
        ),
      ],
    );
  }
}
