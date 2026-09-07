// lib/screens/exam_import_screen.dart
//
// Exam Intelligence — step 1: import a college result spreadsheet for one
// named exam sitting (e.g. "MBBS 1st Year 2nd Internal Assessment"). A
// blocked import (a subject with no stated max, a mark above its max, or a
// student name that doesn't match anyone on file) is shown inline, not
// thrown as an error — it's the expected outcome for a sheet that needs a
// person's attention before anything is written.

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../widgets/glass_widgets.dart';
import 'exam_cohort_screen.dart';

class ExamImportScreen extends StatefulWidget {
  const ExamImportScreen({super.key});

  @override
  State<ExamImportScreen> createState() => _ExamImportScreenState();
}

class _ExamImportScreenState extends State<ExamImportScreen> {
  final ApiService _api = ApiService();
  final _examGroupController = TextEditingController();
  final _reasonController = TextEditingController();

  String? _filePath;
  String? _fileName;
  String _mode = 'strict';
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _examGroupController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['xlsx']);
    if (picked == null || picked.path == null) return;
    setState(() {
      _filePath = picked.path;
      _fileName = picked.name;
      _result = null;
      _error = null;
    });
  }

  Future<void> _import() async {
    if (_filePath == null || _fileName == null) return;
    if (_examGroupController.text.trim().isEmpty) {
      setState(() => _error = 'Name this exam sitting first (e.g. "2nd Internal Assessment")');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _api.importExamMarks(
        filePath: _filePath!,
        fileName: _fileName!,
        examGroup: _examGroupController.text.trim(),
        mode: _mode,
        reason: _mode == 'amend' ? _reasonController.text.trim() : null,
      );
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
    final blocked = _result != null && _result!['blocked'] == true;
    final succeeded = _result != null && _result!['blocked'] != true;

    return Scaffold(
      appBar: AppBar(title: const Text('Import Exam Results')),
      body: GlassBackdrop(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _examGroupController,
                    decoration: const InputDecoration(
                      labelText: 'Exam sitting name',
                      hintText: 'e.g. MBBS 1st Year 2nd Internal Assessment',
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassButton(
                    onPressed: _loading ? null : _pickFile,
                    icon: Icons.upload_file,
                    child: Text(_fileName ?? 'Choose .xlsx result sheet'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          value: 'strict',
                          groupValue: _mode,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('New marks only', style: TextStyle(fontSize: 13)),
                          onChanged: (v) => setState(() => _mode = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          value: 'amend',
                          groupValue: _mode,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Correcting marks', style: TextStyle(fontSize: 13)),
                          onChanged: (v) => setState(() => _mode = v!),
                        ),
                      ),
                    ],
                  ),
                  if (_mode == 'amend')
                    TextField(
                      controller: _reasonController,
                      decoration: const InputDecoration(labelText: 'Reason for the correction (required)'),
                    ),
                  const SizedBox(height: 12),
                  GlassButton(
                    onPressed: _loading || _filePath == null ? null : _import,
                    icon: Icons.publish,
                    child: const Text('Import'),
                  ),
                ],
              ),
            ),
            if (_loading) const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            if (blocked) ...[
              const SizedBox(height: 16),
              GlassContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: const [
                      Icon(Icons.block, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Import blocked', style: TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 8),
                    Text(_result!['blockedReason']?.toString() ?? 'Unknown reason'),
                    const SizedBox(height: 8),
                    ..._blockedDetailLines(_result!['blockedDetails']),
                  ],
                ),
              ),
            ],
            if (succeeded) ...[
              const SizedBox(height: 16),
              GlassContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Import complete', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('${_result!['summary']?['inserted'] ?? 0} marks inserted'),
                    Text('${_result!['summary']?['revised'] ?? 0} marks revised'),
                    Text('${_result!['summary']?['unchanged'] ?? 0} unchanged'),
                    const SizedBox(height: 12),
                    GlassButton(
                      icon: Icons.list,
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => ExamCohortScreen(examGroup: _examGroupController.text.trim())),
                      ),
                      child: const Text('View results'),
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

  List<Widget> _blockedDetailLines(dynamic details) {
    if (details is! List) return [];
    return details.take(10).map<Widget>((d) {
      if (d is Map) {
        final subject = d['subject'] ?? d['student'] ?? '';
        final hint = d['highestMarkSeen'] != null
            ? 'highest mark seen: ${d['highestMarkSeen']}'
            : (d['marks'] != null ? '${d['marks']} > max ${d['max']}' : '');
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('• $subject${hint.isNotEmpty ? ' ($hint)' : ''}', style: const TextStyle(fontSize: 12)),
        );
      }
      return Padding(padding: const EdgeInsets.only(top: 2), child: Text('• $d', style: const TextStyle(fontSize: 12)));
    }).toList();
  }
}
