import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getCampaigns();
  }

  void _refresh() => setState(() => _future = _api.getCampaigns());

  Future<void> _createDialog() async {
    final nameCtrl = TextEditingController();
    final messageCtrl = TextEditingController(text: 'Hi {{name}}, ');
    final sourceCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Campaign'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Campaign Name')),
            TextField(
              controller: messageCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Message ({{name}} = lead\'s name)'),
            ),
            TextField(controller: sourceCtrl, decoration: const InputDecoration(labelText: 'Target source (optional, e.g. Website)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (saved == true && nameCtrl.text.trim().isNotEmpty && messageCtrl.text.trim().isNotEmpty) {
      await _api.createCampaign(
        name: nameCtrl.text.trim(),
        messageTemplate: messageCtrl.text.trim(),
        source: sourceCtrl.text.trim().isEmpty ? null : sourceCtrl.text.trim(),
      );
      _refresh();
    }
  }

  void _openSendSheet(String campaignId, String name) async {
    final data = await _api.getCampaignLinks(campaignId);
    final links = (data['links'] as List).cast<Map<String, dynamic>>();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: links.length,
                itemBuilder: (context, i) {
                  final l = links[i];
                  final sent = l['status'] == 'sent';
                  return ListTile(
                    title: Text(l['full_name']),
                    trailing: sent
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : IconButton(
                            icon: const Icon(Icons.chat, color: Colors.green),
                            onPressed: () async {
                              await launchUrl(Uri.parse(l['chat_link']), mode: LaunchMode.externalApplication);
                              await _api.confirmCampaignTargetSent(l['target_id']);
                              Navigator.pop(context);
                              _openSendSheet(campaignId, name); // reopen refreshed
                            },
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Campaigns')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final campaigns = snapshot.data ?? [];
            if (campaigns.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 100),
                  Center(child: Text('No campaigns yet', style: TextStyle(color: Colors.grey))),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: campaigns.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = campaigns[i];
                return ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: Text(c['name']),
                  subtitle: Text('${c['sent_count']}/${c['target_count']} sent'),
                  onTap: () => _openSendSheet(c['id'], c['name']),
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
