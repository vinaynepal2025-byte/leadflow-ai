import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class DocumentsScreen extends StatefulWidget {
  final String leadId;
  const DocumentsScreen({super.key, required this.leadId});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocPick {
  final String docType;
  final String? expiryDate;
  _DocPick(this.docType, this.expiryDate);
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final ApiService _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;
  bool _uploading = false;

  static const _fallbackDocTypes = ['Passport', 'Marksheet', 'Photo', 'Certificate', 'Bank Statement', 'Other'];

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
    final picked = await _askDocTypeAndExpiry();
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      await _api.uploadDocument(
        leadId: widget.leadId,
        docType: picked.docType,
        filePath: file.path!,
        fileName: file.name,
        uploadedBy: 'Counselor',
        expiryDate: picked.expiryDate,
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

  Future<_DocPick?> _askDocTypeAndExpiry() async {
    // Pulls in whatever this lead's active visa checklists actually
    // require (e.g. "I-20 Form", "CAS Letter") on top of the universal
    // defaults, so the type picked here can exact-match the checklist
    // instead of everything specialized falling into "Other".
    List<String> types;
    try {
      types = await _api.getDocTypes(widget.leadId);
    } catch (_) {
      types = _fallbackDocTypes;
    }

    String? selected;
    final customCtrl = TextEditingController();
    DateTime? expiry;

    return showDialog<_DocPick>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Document details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: types.map((t) {
                    return ChoiceChip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      selected: selected == t,
                      onSelected: (_) => setDialogState(() => selected = t),
                    );
                  }).toList(),
                ),
                TextField(
                  controller: customCtrl,
                  decoration: const InputDecoration(labelText: 'Or type a custom name'),
                  onChanged: (v) => setDialogState(() => selected = null),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Expiry (optional): '),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 15)),
                        );
                        if (picked != null) setDialogState(() => expiry = picked);
                      },
                      child: Text(expiry == null
                          ? 'Set date'
                          : '${expiry!.year}-${expiry!.month.toString().padLeft(2, '0')}-${expiry!.day.toString().padLeft(2, '0')}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final docType = customCtrl.text.trim().isNotEmpty ? customCtrl.text.trim() : selected;
                if (docType == null) return;
                Navigator.pop(
                  context,
                  _DocPick(
                    docType,
                    expiry == null
                        ? null
                        : '${expiry!.year}-${expiry!.month.toString().padLeft(2, '0')}-${expiry!.day.toString().padLeft(2, '0')}',
                  ),
                );
              },
              child: const Text('Continue'),
            ),
          ],
        ),
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
              final expiryDate = d['expiry_date'] as String?;
              final isExpired = expiryDate != null && DateTime.tryParse(expiryDate)?.isBefore(DateTime.now()) == true;
              return ListTile(
                leading: Icon(Icons.description_outlined, color: _statusColor(d['status'])),
                title: Text(d['doc_type']),
                subtitle: Text(
                  expiryDate != null ? '${d['file_name']} • ${isExpired ? 'EXPIRED' : 'expires'} $expiryDate' : d['file_name'],
                  style: isExpired ? const TextStyle(color: Colors.red, fontWeight: FontWeight.w600) : null,
                ),
                trailing: Chip(
                  label: Text(d['status'], style: const TextStyle(fontSize: 11)),
                  backgroundColor: _statusColor(d['status']).withValues(alpha: 0.12),
                  labelStyle: TextStyle(color: _statusColor(d['status'])),
                ),
                onTap: () => _showDocumentOptions(d),
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

  Future<void> _showDocumentOptions(Map<String, dynamic> d) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('View / Download'),
              subtitle: Text(d['file_name']),
              onTap: () async {
                Navigator.pop(context);
                final url = _api.getDocumentDownloadUrl(d['id']);
                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
            ),
            if (d['status'] == 'pending') ...[
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('Verify'),
                onTap: () async {
                  Navigator.pop(context);
                  await _api.setDocumentStatus(d['id'], 'verified');
                  _refresh();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.red),
                title: const Text('Reject'),
                onTap: () async {
                  Navigator.pop(context);
                  await _api.setDocumentStatus(d['id'], 'rejected');
                  _refresh();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
