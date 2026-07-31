import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PipelineBuilderScreen extends StatefulWidget {
  const PipelineBuilderScreen({super.key});

  @override
  State<PipelineBuilderScreen> createState() => _PipelineBuilderScreenState();
}

class _PipelineBuilderScreenState extends State<PipelineBuilderScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getPipelineStages();
  }

  void _refresh() => setState(() => _future = _api.getPipelineStages());

  Future<void> _addDialog() async {
    final nameCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Stage'),
        content: TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Visa Applied')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      await _api.createPipelineStage(name: nameCtrl.text.trim());
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pipeline Builder')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'These stages appear on every lead, in this order. Add, rename, '
              'or remove stages to match how your consultancy actually works.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final stages = snapshot.data ?? [];
                return ListView.separated(
                  itemCount: stages.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = stages[i];
                    final color = Color(int.parse((s['color'] as String? ?? '#607D8B').substring(1), radix: 16) + 0xFF000000);
                    return ListTile(
                      leading: CircleAvatar(backgroundColor: color, radius: 10),
                      title: Text(s['name']),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () async {
                          await _api.deletePipelineStage(s['id']);
                          _refresh();
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addDialog, child: const Icon(Icons.add)),
    );
  }
}
