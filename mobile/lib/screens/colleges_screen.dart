import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CollegesScreen extends StatefulWidget {
  const CollegesScreen({super.key});

  @override
  State<CollegesScreen> createState() => _CollegesScreenState();
}

class _CollegesScreenState extends State<CollegesScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getColleges();
  }

  void _refresh() => setState(() => _future = _api.getColleges());

  Future<void> _addDialog() async {
    final nameCtrl = TextEditingController();
    final countryCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final commissionCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add College/University'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: countryCtrl, decoration: const InputDecoration(labelText: 'Country')),
              TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contact Person')),
              TextField(controller: commissionCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Commission %')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      await _api.createCollege(
        name: nameCtrl.text.trim(),
        country: countryCtrl.text.trim().isEmpty ? null : countryCtrl.text.trim(),
        contactPerson: contactCtrl.text.trim().isEmpty ? null : contactCtrl.text.trim(),
        commissionPercent: double.tryParse(commissionCtrl.text.trim()),
      );
      _refresh();
    }
  }

  // Tenant-controllable per-college peer-review config: on/off + default
  // price. This is the lever that makes the paid peer-review marketplace
  // opt-in per college rather than a blanket platform feature.
  Future<void> _peerReviewDialog(Map<String, dynamic> college) async {
    bool enabled = college['peer_review_enabled'] == true;
    final priceCtrl = TextEditingController(text: college['peer_review_default_price']?.toString() ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Peer Review — ${college['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Enable paid peer review'),
                subtitle: const Text('Lets verified students/alumni offer paid review calls for this college'),
                value: enabled,
                onChanged: (v) => setDialogState(() => enabled = v),
              ),
              if (enabled)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Default price per review (₹)', helperText: 'Individual providers can override this'),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved == true) {
      await _api.updateCollege(college['id'], {
        'peer_review_enabled': enabled,
        if (enabled) 'peer_review_default_price': double.tryParse(priceCtrl.text.trim()),
      });
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Colleges & Universities')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final colleges = snapshot.data ?? [];
          if (colleges.isEmpty) {
            return const Center(child: Text('No partner colleges added yet', style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            itemCount: colleges.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = colleges[i];
              final reviewOn = c['peer_review_enabled'] == true;
              return ListTile(
                leading: const Icon(Icons.school_outlined),
                title: Text(c['name']),
                subtitle: Text(
                  '${c['country'] ?? ''} ${c['contact_person'] != null ? '• ${c['contact_person']}' : ''}'
                  '${reviewOn ? '\n⭐ Peer review ON — ₹${c['peer_review_default_price'] ?? '—'}' : ''}',
                ),
                isThreeLine: reviewOn,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c['commission_percent'] != null) Text('${c['commission_percent']}%'),
                    IconButton(
                      icon: Icon(Icons.star, color: reviewOn ? Colors.amber : Colors.grey),
                      tooltip: 'Peer review settings',
                      onPressed: () => _peerReviewDialog(c),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addDialog, child: const Icon(Icons.add)),
    );
  }
}
