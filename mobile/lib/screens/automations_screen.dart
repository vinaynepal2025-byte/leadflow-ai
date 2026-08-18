import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AutomationsScreen extends StatefulWidget {
  const AutomationsScreen({super.key});

  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  static const triggers = ['lead.created', 'lead.stage_changed', 'lead.lifecycle_status_changed', 'document.rejected'];

  @override
  void initState() {
    super.initState();
    _future = _api.getAutomations();
  }

  void _refresh() => setState(() => _future = _api.getAutomations());

  Future<void> _createDialog() async {
    final nameCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    String trigger = triggers.first;
    final offsetCtrl = TextEditingController(text: '1');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Automation'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Rule Name')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: trigger,
                  decoration: const InputDecoration(labelText: 'When this happens'),
                  items: triggers.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setDialogState(() => trigger = v ?? trigger),
                ),
                const SizedBox(height: 8),
                const Align(alignment: Alignment.centerLeft, child: Text('Then: create a reminder')),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Reminder title')),
                TextField(controller: offsetCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Days from now')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
          ],
        ),
      ),
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty && titleCtrl.text.trim().isNotEmpty) {
      await _api.createAutomation(
        name: nameCtrl.text.trim(),
        triggerEvent: trigger,
        actionType: 'create_reminder',
        actionConfig: {'title': titleCtrl.text.trim(), 'offset_days': int.tryParse(offsetCtrl.text) ?? 1},
      );
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Automation Hub')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final rules = snapshot.data ?? [];
            if (rules.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 100),
                  Center(child: Text('No automation rules yet', style: TextStyle(color: Colors.grey))),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: rules.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = rules[i];
                return ListTile(
                  leading: const Icon(Icons.bolt_outlined, color: Colors.deepPurple),
                  title: Text(r['name']),
                  subtitle: Text('${r['trigger_event']} → ${r['action_type']}'),
                  trailing: Switch(
                    value: r['enabled'] == 1,
                    onChanged: (v) async {
                      await _api.setAutomationEnabled(r['id'], v);
                      _refresh();
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: _createDialog, child: const Icon(Icons.add)),
    );
  }
}
