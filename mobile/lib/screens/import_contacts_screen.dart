import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class ImportContactsScreen extends StatefulWidget {
  const ImportContactsScreen({super.key});

  @override
  State<ImportContactsScreen> createState() => _ImportContactsScreenState();
}

class _ImportContactsScreenState extends State<ImportContactsScreen> {
  final _api = ApiService();
  bool _importing = false;
  Map<String, dynamic>? _result;
  String? _error;

  Future<void> _pickAndImport({required bool isExcel}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: isExcel ? ['xlsx'] : ['csv'],
    );
    if (result == null || result.files.single.path == null) return;

    setState(() {
      _importing = true;
      _error = null;
      _result = null;
    });
    try {
      final res = isExcel
          ? await _api.importLeadsExcel(result.files.single.path!, result.files.single.name)
          : await _api.importLeadsCsv(result.files.single.path!, result.files.single.name);
      setState(() => _result = res);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Contacts')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CSV format expected:', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('full_name, phone, email, source, notes', style: TextStyle(fontFamily: 'monospace')),
                    SizedBox(height: 8),
                    Text('Only full_name is required. Leads with a phone number '
                        'that already exists are automatically skipped as duplicates.',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _importing ? null : () => _pickAndImport(isExcel: false),
              icon: _importing
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_file),
              label: Text(_importing ? 'Importing...' : 'Choose CSV File'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _importing ? null : () => _pickAndImport(isExcel: true),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Choose Excel (.xlsx) File'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 20),
              Card(
                color: Colors.green.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_result!['created']} leads created', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${_result!['skipped_duplicate']} skipped (duplicate phone)'),
                      Text('${_result!['skipped_invalid']} skipped (missing name)'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
