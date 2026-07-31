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
              return ListTile(
                leading: const Icon(Icons.school_outlined),
                title: Text(c['name']),
                subtitle: Text('${c['country'] ?? ''} ${c['contact_person'] != null ? '• ${c['contact_person']}' : ''}'),
                trailing: c['commission_percent'] != null ? Text('${c['commission_percent']}%') : null,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addDialog, child: const Icon(Icons.add)),
    );
  }
}
