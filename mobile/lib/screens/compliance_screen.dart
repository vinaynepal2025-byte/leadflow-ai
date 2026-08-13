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
  Map<String, Map<String, dynamic>> _templates = {};

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
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    try {
      final list = await _api.getConsentTemplates();
      if (!mounted) return;
      setState(() => _templates = {for (final t in list) t['consent_type'] as String: t});
    } catch (_) {
      // Non-critical — toggles still work without the legal-language viewer.
    }
  }

  void _refresh() => setState(() => _future = _api.getConsent(widget.leadId));

  Future<void> _toggleConsent(String type, bool current) async {
    await _api.recordConsent(leadId: widget.leadId, consentType: type, granted: !current, method: 'app');
    _refresh();
  }

  void _showLegalLanguage(String type) {
    final t = _templates[type];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t?['title'] as String? ?? consentLabels[type]!),
        content: SingleChildScrollView(
          child: Text(t?['body_text'] as String? ?? 'No custom language configured for this consent type yet — using the default label only.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _editLegalLanguage(type);
            },
            child: const Text('Edit wording'),
          ),
        ],
      ),
    );
  }

  Future<void> _editLegalLanguage(String type) async {
    final t = _templates[type];
    final titleCtrl = TextEditingController(text: t?['title'] as String? ?? consentLabels[type]);
    final bodyCtrl = TextEditingController(text: t?['body_text'] as String? ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Customize consent language'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
              TextField(controller: bodyCtrl, decoration: const InputDecoration(labelText: 'Legal text shown to the lead'), maxLines: 6),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true && titleCtrl.text.trim().isNotEmpty && bodyCtrl.text.trim().isNotEmpty) {
      await _api.saveConsentTemplate(consentType: type, title: titleCtrl.text.trim(), bodyText: bodyCtrl.text.trim());
      _loadTemplates();
    }
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
                  secondary: IconButton(
                    icon: const Icon(Icons.info_outline, size: 20),
                    tooltip: 'View/edit legal language',
                    onPressed: () => _showLegalLanguage(type),
                  ),
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
