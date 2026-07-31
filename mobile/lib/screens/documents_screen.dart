import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class DocumentsScreen extends StatefulWidget {
  final String leadId;
  const DocumentsScreen({super.key, required this.leadId});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final ApiService _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;
  bool _uploading = false;

  static const docTypes = ['Passport', 'Marksheet', 'Photo', 'Certificate', 'Other'];

  @override
  void initState() {
    super.initState();
    _future = _api.getDocuments(widget.leadId);
  }

  void _refresh() => setState(() => _future = _api.getDocuments(widget.leadId));

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    final file = result.files.single;
    final docType = await _askDocType();
    if (docType == null) return;

    setState(() => _uploading = true);
    try {
      await _api.uploadDocument(
        leadId: widget.leadId,
        docType: docType,
        filePath: file.path!,
        fileName: file.name,
        uploadedBy: 'Counselor',
      );
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<String?> _askDocType() {
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('What type of document?'),
        children: docTypes
            .map((t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, t),
                  child: Text(t),
                ))
            .toList(),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'verified':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No documents uploaded yet', style: TextStyle(color: Colors.grey)),
            );
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              return ListTile(
                leading: Icon(Icons.description_outlined, color: _statusColor(d['status'])),
                title: Text(d['doc_type']),
                subtitle: Text(d['file_name']),
                trailing: Chip(
                  label: Text(d['status'], style: const TextStyle(fontSize: 11)),
                  backgroundColor: _statusColor(d['status']).withValues(alpha: 0.12),
                  labelStyle: TextStyle(color: _statusColor(d['status'])),
                ),
                onTap: d['status'] == 'pending'
                    ? () => _showVerifyOptions(d['id'])
                    : null,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _pickAndUpload,
        icon: _uploading
            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.upload_file),
        label: Text(_uploading ? 'Uploading...' : 'Upload'),
      ),
    );
  }

  void _showVerifyOptions(String docId) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('Verify'),
              onTap: () async {
                Navigator.pop(context);
                await _api.setDocumentStatus(docId, 'verified');
                _refresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.red),
              title: const Text('Reject'),
              onTap: () async {
                Navigator.pop(context);
                await _api.setDocumentStatus(docId, 'rejected');
                _refresh();
              },
            ),
          ],
        ),
      ),
    );
  }
}
