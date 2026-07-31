import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class SocialLinksScreen extends StatefulWidget {
  const SocialLinksScreen({super.key});

  @override
  State<SocialLinksScreen> createState() => _SocialLinksScreenState();
}

class _SocialLinksScreenState extends State<SocialLinksScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _linksFuture;
  late Future<List<Map<String, dynamic>>> _formsFuture;

  static const platforms = ['instagram', 'facebook', 'whatsapp', 'telegram', 'youtube', 'linkedin', 'tiktok', 'offline_qr', 'other'];

  @override
  void initState() {
    super.initState();
    _linksFuture = _api.getTrackedLinks();
    _formsFuture = _api.getCaptureForms();
  }

  void _refresh() => setState(() => _linksFuture = _api.getTrackedLinks());

  Future<void> _createDialog() async {
    final forms = await _formsFuture;
    if (forms.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create a Lead Capture Form first (in More menu)')),
        );
      }
      return;
    }

    final titleCtrl = TextEditingController();
    final campaignCtrl = TextEditingController();
    String platform = platforms.first;
    String? formId = forms.first['id'];

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Trackable Link'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title (e.g. "Instagram bio link")')),
                DropdownButtonFormField<String>(
                  initialValue: platform,
                  decoration: const InputDecoration(labelText: 'Platform'),
                  items: platforms.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                  onChanged: (v) => setDialogState(() => platform = v ?? platform),
                ),
                DropdownButtonFormField<String>(
                  initialValue: formId,
                  decoration: const InputDecoration(labelText: 'Sends leads to which form?'),
                  items: forms.map<DropdownMenuItem<String>>((f) => DropdownMenuItem(value: f['id'] as String, child: Text(f['name']))).toList(),
                  onChanged: (v) => setDialogState(() => formId = v),
                ),
                TextField(controller: campaignCtrl, decoration: const InputDecoration(labelText: 'Campaign (optional)')),
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

    if (saved == true && titleCtrl.text.trim().isNotEmpty) {
      await _api.createTrackedLink(
        title: titleCtrl.text.trim(),
        platform: platform,
        captureFormId: formId,
        campaign: campaignCtrl.text.trim().isEmpty ? null : campaignCtrl.text.trim(),
      );
      _refresh();
    }
  }

  void _showShareSheet(Map<String, dynamic> link) {
    final url = '${ApiService.baseUrl}/s/${link['short_code']}';
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(url, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.chat, color: Colors.green),
              title: const Text('Share via WhatsApp'),
              onTap: () {
                Navigator.pop(context);
                launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(url)}'), mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.telegram, color: Colors.blue),
              title: const Text('Share via Telegram'),
              onTap: () {
                Navigator.pop(context);
                launchUrl(Uri.parse('https://t.me/share/url?url=${Uri.encodeComponent(url)}'), mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code, color: Colors.black87),
              title: const Text('Show QR Code'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    content: Image.network('${ApiService.baseUrl}/social/links/${link['id']}/qr', width: 250, height: 250),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Social Media Links')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _linksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final links = snapshot.data ?? [];
          if (links.isEmpty) {
            return const Center(child: Text('No trackable links yet', style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            itemCount: links.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final l = links[i];
              return ListTile(
                leading: const Icon(Icons.link),
                title: Text(l['title']),
                subtitle: Text('${l['platform']}${l['campaign'] != null ? ' • ${l['campaign']}' : ''} • ${l['click_count']} clicks'),
                trailing: IconButton(icon: const Icon(Icons.share), onPressed: () => _showShareSheet(l)),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _createDialog, child: const Icon(Icons.add)),
    );
  }
}
