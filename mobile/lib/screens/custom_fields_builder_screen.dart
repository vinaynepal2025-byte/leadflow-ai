import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CustomFieldsBuilderScreen extends StatefulWidget {
  const CustomFieldsBuilderScreen({super.key});

  @override
  State<CustomFieldsBuilderScreen> createState() => _CustomFieldsBuilderScreenState();
}

class _CustomFieldsBuilderScreenState extends State<CustomFieldsBuilderScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  static const types = ['text', 'number', 'date', 'select'];

  @override
  void initState() {
    super.initState();
    _future = _api.getCustomFieldDefinitions();
  }

  void _refresh() => setState(() => _future = _api.getCustomFieldDefinitions());

  Future<void> _addDialog() async {
    final labelCtrl = TextEditingController();
    final optionsCtrl = TextEditingController();
    String type = 'text';
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Custom Field'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'Field Label (e.g. IELTS Score)')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setDialogState(() => type = v ?? type),
                ),
                if (type == 'select') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: optionsCtrl,
                    decoration: const InputDecoration(labelText: 'Options, comma-separated'),
                  ),
                ],
                if (error != null) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (labelCtrl.text.trim().isEmpty) return;
                final key = labelCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
                try {
                  await _api.createCustomFieldDefinition(
                    fieldKey: key,
                    label: labelCtrl.text.trim(),
                    fieldType: type,
                    options: type == 'select'
                        ? optionsCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
                        : null,
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  setDialogState(() => error = e.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) _refresh();
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'number':
        return Icons.tag;
      case 'date':
        return Icons.calendar_today;
      case 'select':
        return Icons.list;
      default:
        return Icons.short_text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom Fields')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final fields = snapshot.data ?? [];
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Add fields specific to your consultancy — they\'ll appear on every lead\'s detail screen.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
              Expanded(
                child: fields.isEmpty
                    ? const Center(child: Text('No custom fields yet', style: TextStyle(color: Colors.grey)))
                    : ListView.separated(
                        itemCount: fields.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final f = fields[i];
                          return ListTile(
                            leading: Icon(_iconFor(f['field_type'])),
                            title: Text(f['label']),
                            subtitle: Text(f['field_type']),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () async {
                                await _api.deleteCustomFieldDefinition(f['id']);
                                _refresh();
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addDialog, child: const Icon(Icons.add)),
    );
  }
}
