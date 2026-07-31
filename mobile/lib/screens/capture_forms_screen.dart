import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class CaptureFormsScreen extends StatefulWidget {
  const CaptureFormsScreen({super.key});

  @override
  State<CaptureFormsScreen> createState() => _CaptureFormsScreenState();
}

class _CaptureFormsScreenState extends State<CaptureFormsScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  static const channels = ['website', 'qr', 'facebook', 'whatsapp', 'other'];

  @override
  void initState() {
    super.initState();
    _future = _api.getCaptureForms();
  }

  void _refresh() => setState(() => _future = _api.getCaptureForms());

  Future<void> _createDialog() async {
    final nameCtrl = TextEditingController();
    final replyCtrl = TextEditingController(text: 'Thank you! We will contact you shortly.');
    String channel = channels.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Lead Capture Form'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Form Name')),
                DropdownButtonFormField<String>(
                  value: channel,
                  decoration: const InputDecoration(labelText: 'Channel'),
                  items: channels.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDialogState(() => channel = v ?? channel),
                ),
                TextField(controller: replyCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Auto-reply message')),
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

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      await _api.createCaptureForm(name: nameCtrl.text.trim(), channel: channel, autoReplyMessage: replyCtrl.text.trim());
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lead Capture Forms')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Each form gets its own public link — paste it on your website, in a QR code, or your Instagram bio. Every submission becomes a lead automatically.',
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
                final forms = snapshot.data ?? [];
                if (forms.isEmpty) {
                  return const Center(child: Text('No forms yet', style: TextStyle(color: Colors.grey)));
                }
                return ListView.separated(
                  itemCount: forms.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final f = forms[i];
                    final url = '${ApiService.baseUrl}/capture/form/${f['public_key']}';
                    return ListTile(
                      leading: const Icon(Icons.assignment_outlined),
                      title: Text(f['name']),
                      subtitle: Text('${f['channel']} • ${f['submission_count']} submissions'),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
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
      floatingActionButton: FloatingActionButton(onPressed: _createDialog, child: const Icon(Icons.add)),
    );
  }
}
