// lib/screens/cockpit_screen.dart
//
// Calling Cockpit — Phase 1
// One-screen workspace for a single lead: full history (via the existing
// lead detail data), AI Next Best Action, offer tracking, and the
// personalized Draft -> WhatsApp-safe Send flow.
//
// WhatsApp-safety design (do not change without re-reading the reasoning):
// this screen NEVER sends a WhatsApp message programmatically. It opens
// the pre-filled wa.me chat (via the existing getWhatsAppChatLink flow,
// same as Lead Detail's WhatsApp button) and the counselor taps Send
// themselves inside WhatsApp. confirmCockpitSend() only logs that a send
// happened — call it right after launchUrl succeeds.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';
import 'flyer_studio/flyer_history_screen.dart';

class CockpitScreen extends StatefulWidget {
  final String leadId;
  const CockpitScreen({super.key, required this.leadId});

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen> {
  final ApiService _api = ApiService();

  bool _loading = true;
  String? _loadError;
  Map<String, dynamic>? _cockpit; // lead + communications + offers
  List<Map<String, dynamic>> _offers = [];

  bool _nbaLoading = false;
  Map<String, dynamic>? _nba; // next-best-action result
  String? _nbaError;

  bool _draftLoading = false;
  Map<String, dynamic>? _draft;
  String? _draftError;
  final TextEditingController _draftController = TextEditingController();
  bool _sending = false;
  bool _whatsappApiConfigured = false;
  bool _sendViaApi = false;
  Map<String, dynamic>? _finance; // fees + documents for this lead

  @override
  void initState() {
    super.initState();
    _load();
    _api.checkWhatsAppApiConfigured().then((configured) {
      if (mounted) setState(() => _whatsappApiConfigured = configured);
    });
  }

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final cockpit = await _api.getCockpit(widget.leadId);
      final finance = await _api.getFinanceSummary(widget.leadId);
      setState(() {
        _cockpit = cockpit;
        _offers = (cockpit['offers'] as List).cast<Map<String, dynamic>>();
        _finance = finance;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fetchNextBestAction() async {
    setState(() {
      _nbaLoading = true;
      _nbaError = null;
    });
    try {
      final result = await _api.getNextBestAction(widget.leadId);
      setState(() {
        _nba = result;
        _nbaLoading = false;
      });
    } catch (e) {
      setState(() {
        _nbaError = e.toString();
        _nbaLoading = false;
      });
    }
  }

  Future<void> _fetchDraft() async {
    setState(() {
      _draftLoading = true;
      _draftError = null;
      _draft = null;
    });
    try {
      final result = await _api.getDraft(widget.leadId, channel: 'whatsapp');
      setState(() {
        _draft = result;
        _draftController.text = result['message_text'] ?? '';
        _draftLoading = false;
      });
    } catch (e) {
      setState(() {
        _draftError = e.toString();
        _draftLoading = false;
      });
    }
  }

  // Opens WhatsApp with the (possibly counselor-edited) draft pre-filled,
  // then logs the send. This is a two-step honor-system flow by design —
  // see the file header note on WhatsApp safety.
  Future<void> _openWhatsAppAndLog() async {
    final text = _draftController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      if (_sendViaApi && _whatsappApiConfigured) {
        // Paid path: sends instantly via Meta Cloud API, no manual tap
        // needed. whatsapp.js already logs this to Communication Hub
        // itself, so no separate confirm-send call here.
        await _api.sendViaWhatsAppApi(leadId: widget.leadId, message: text);
      } else {
        final link = await _api.getWhatsAppChatLink(widget.leadId, text);
        await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
        await _api.confirmCockpitSend(
          leadId: widget.leadId,
          channel: 'whatsapp',
          draftText: text,
          contentId: _draft?['attach_content_id'],
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged — go ahead and tap Send inside WhatsApp')),
        );
        setState(() {
          _draft = null;
          _draftController.clear();
        });
        _load(); // refresh history/offers now that a send was logged
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open WhatsApp: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static const _offerStatuses = ['active', 'accepted', 'expired', 'withdrawn'];

  Color _offerStatusColor(String status) {
    switch (status) {
      case 'accepted':
        return AppColors.successGreen;
      case 'expired':
        return AppColors.slate;
      case 'withdrawn':
        return AppColors.coralAlert;
      default:
        return AppColors.signalAmber; // active
    }
  }

  Future<void> _changeOfferStatus(String offerId, String status) async {
    try {
      await _api.updateOfferStatus(offerId, status);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update offer: $e')));
      }
    }
  }

  Future<void> _showAddOfferDialog() async {
    final textCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log an Offer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textCtrl,
              decoration: const InputDecoration(labelText: 'Offer (e.g. "50% scholarship")'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(labelText: 'Amount (₹, optional)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (result != true || textCtrl.text.trim().isEmpty) return;
    try {
      await _api.createOffer(
        leadId: widget.leadId,
        offerText: textCtrl.text.trim(),
        amount: amountCtrl.text.trim().isEmpty ? null : num.tryParse(amountCtrl.text.trim()),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save offer: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final leadName = _cockpit?['lead']?['full_name'] ?? 'Cockpit';

    return Scaffold(
      appBar: AppBar(title: Text(leadName)),
      body: GlassBackdrop(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(child: Text('Could not load: $_loadError'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildNextBestActionCard(),
                        const SizedBox(height: 16),
                        _buildOffersCard(),
                        const SizedBox(height: 16),
                        _buildFinanceCard(),
                        const SizedBox(height: 16),
                        _buildDraftCard(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildNextBestActionCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: Colors.amber),
              const SizedBox(width: 8),
              const Text('Next Best Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              if (_nbaLoading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          if (_nba == null && !_nbaLoading)
            GlassButton(onPressed: _fetchNextBestAction, child: const Text('What should I do now?')),
          if (_nbaError != null) Text(_nbaError!, style: const TextStyle(color: Colors.red)),
          if (_nba != null) ...[
            Row(
              children: [
                Chip(label: Text((_nba!['recommended_channel'] ?? '').toString().toUpperCase())),
                const SizedBox(width: 8),
                Chip(
                  label: Text((_nba!['urgency'] ?? '').toString()),
                  backgroundColor: _nba!['urgency'] == 'today' ? Colors.red.shade100 : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_nba!['reasoning'] ?? ''),
            const SizedBox(height: 8),
            ...((_nba!['talking_points'] as List? ?? []))
                .map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $p'),
                    )),
            if (_nba!['risk_flag'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('⚠️ ${_nba!['risk_flag']}', style: const TextStyle(color: Colors.orange)),
              ),
            TextButton(onPressed: _fetchNextBestAction, child: const Text('Refresh')),
          ],
        ],
      ),
    );
  }

  Widget _buildOffersCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer, color: Colors.green),
              const SizedBox(width: 8),
              const Text('Offers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.add), onPressed: _showAddOfferDialog),
            ],
          ),
          if (_offers.isEmpty) const Text('No offers logged yet', style: TextStyle(color: Colors.grey)),
          ..._offers.map((o) {
            final status = (o['status'] as String?) ?? 'active';
            final color = _offerStatusColor(status);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(o['offer_text'] ?? ''),
              subtitle: Text(o['amount'] != null ? '₹${o['amount']}' : 'No amount specified'),
              trailing: PopupMenuButton<String>(
                initialValue: status,
                onSelected: (v) => _changeOfferStatus(o['id'] as String, v),
                itemBuilder: (ctx) => _offerStatuses
                    .map((s) => PopupMenuItem(value: s, child: Text(s[0].toUpperCase() + s.substring(1))))
                    .toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                      Icon(Icons.arrow_drop_down, size: 16, color: color),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFinanceCard() {
    final fees = (_finance?['fees'] as List? ?? []);
    final documents = (_finance?['documents'] as List? ?? []);
    if (fees.isEmpty && documents.isEmpty) return const SizedBox.shrink();

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.teal),
              SizedBox(width: 8),
              Text('Fees & Documents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          ...fees.map((f) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${f['fee_type']} — ₹${f['amount']}'),
                subtitle: Text('Due ${f['due_date'] ?? 'n/a'} · ${f['status']}'),
                trailing: f['status'] != 'paid'
                    ? TextButton(
                        onPressed: () async {
                          await _api.markFeePaidFromCockpit(leadId: widget.leadId, feeId: f['id']);
                          _load();
                        },
                        child: const Text('Mark Paid'),
                      )
                    : const Icon(Icons.check_circle, color: Colors.green, size: 20),
              )),
          if (documents.isNotEmpty) ...[
            const Divider(),
            ...documents.map((d) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(d['doc_type'] ?? ''),
                  trailing: Chip(
                    label: Text(d['status'] ?? ''),
                    backgroundColor: d['status'] == 'verified'
                        ? Colors.green.shade100
                        : d['status'] == 'rejected'
                            ? Colors.red.shade100
                            : null,
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildDraftCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note, color: Colors.blue),
              const SizedBox(width: 8),
              const Text('Draft a message', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FlyerHistoryScreen(leadId: widget.leadId)),
                ),
                icon: const Icon(Icons.image, size: 18),
                label: const Text('Flyer'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_draft == null && !_draftLoading)
            GlassButton(onPressed: _fetchDraft, child: const Text('Draft a personalized WhatsApp message')),
          if (_draftLoading) const Center(child: CircularProgressIndicator()),
          if (_draftError != null) Text(_draftError!, style: const TextStyle(color: Colors.red)),
          if (_draft != null) ...[
            TextField(
              controller: _draftController,
              maxLines: 5,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Edit before sending if needed'),
            ),
            const SizedBox(height: 4),
            Text(_draft!['reasoning'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            if (_whatsappApiConfigured)
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _sendViaApi,
                title: const Text('Send instantly via WhatsApp API', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Off = free tap-to-send in the WhatsApp app', style: TextStyle(fontSize: 11)),
                onChanged: (v) => setState(() => _sendViaApi = v),
              ),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    onPressed: _sending ? null : _openWhatsAppAndLog,
                    icon: _sendViaApi && _whatsappApiConfigured ? Icons.bolt : Icons.send,
                    child: Text(_sending
                        ? 'Sending...'
                        : (_sendViaApi && _whatsappApiConfigured ? 'Send Now (API)' : 'Open WhatsApp & Send')),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _fetchDraft, child: const Text('Redraft')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
