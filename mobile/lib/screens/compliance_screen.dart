import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ComplianceScreen extends StatefulWidget {
  final String leadId;
  final String leadName;
  const ComplianceScreen({super.key, required this.leadId, required this.leadName});

  @override
  State<ComplianceScreen> createState() => _ComplianceScreenState();
}

class _ComplianceScreenState extends State<ComplianceScreen> {
  final _api = ApiService();
  late Future<Map<String, dynamic>> _future;

  static const consentTypes = ['data_processing', 'marketing_contact', 'document_sharing', 'third_party_sharing'];
  static const consentLabels = {
    'data_processing': 'Data Processing',
    'marketing_contact': 'Marketing Contact',
    'document_sharing': 'Document Sharing',
    'third_party_sharing': 'Third-Party Sharing (e.g. with a university)',
  };

  @override
  void initState() {
    super.initState();
    _future = _api.getConsent(widget.leadId);
  }

  void _refresh() => setState(() => _future = _api.getConsent(widget.leadId));

  Future<void> _toggleConsent(String type, bool current) async {
    await _api.recordConsent(leadId: widget.leadId, consentType: type, granted: !current, method: 'app');
    _refresh();
  }

  Future<void> _exportData() async {
    final data = await _api.exportLeadData(widget.leadId);
    if (!mounted) return;
    final tableCounts = data.entries.where((e) => e.key != 'lead').map((e) => '${e.key}: ${(e.value as List).length}').join('\n');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Data Export Ready'),
        content: SingleChildScrollView(child: Text('Everything held on ${widget.leadName}:\n\n$tableCounts')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _requestErasure() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erase All Data?'),
        content: Text('This permanently deletes ${widget.leadName} and every record linked to them — communications, documents, payments, everything. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Erase Permanently'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _api.eraseLeadData(widget.leadId);
      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consent & Compliance')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final current = (snapshot.data?['current'] as Map<String, dynamic>? ?? {});

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Consent Log', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ...consentTypes.map((type) {
                final record = current[type];
                final granted = record != null && record['granted'] == 1;
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(consentLabels[type]!),
                  subtitle: record != null
                      ? Text('Last updated ${record['recorded_at']}', style: const TextStyle(fontSize: 11))
                      : const Text('Not recorded yet', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  value: granted,
                  onChanged: (v) => _toggleConsent(type, granted),
                );
              }),
              const SizedBox(height: 24),
              const Text('Data Rights', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export All Data (Right to Access)'),
                onPressed: _exportData,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                label: const Text('Erase All Data (Right to be Forgotten)', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                onPressed: _requestErasure,
              ),
            ],
          );
        },
      ),
    );
  }
}
