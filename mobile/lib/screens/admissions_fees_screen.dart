import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class AdmissionsFeesScreen extends StatelessWidget {
  final String leadId;
  const AdmissionsFeesScreen({super.key, required this.leadId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admissions & Fees'),
          bottom: const TabBar(tabs: [Tab(text: 'Applications'), Tab(text: 'Fees')]),
        ),
        body: TabBarView(
          children: [
            _AdmissionsTab(leadId: leadId),
            _FeesTab(leadId: leadId),
          ],
        ),
      ),
    );
  }
}

class _AdmissionsTab extends StatefulWidget {
  final String leadId;
  const _AdmissionsTab({required this.leadId});

  @override
  State<_AdmissionsTab> createState() => _AdmissionsTabState();
}

class _AdmissionsTabState extends State<_AdmissionsTab> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  static const stages = ['Preparing', 'Submitted', 'Under Review', 'Offer', 'Accepted', 'Rejected', 'Withdrawn'];

  @override
  void initState() {
    super.initState();
    _future = _api.getAdmissions(widget.leadId);
  }

  void _refresh() => setState(() => _future = _api.getAdmissions(widget.leadId));

  Future<void> _addDialog() async {
    final nameCtrl = TextEditingController();
    final courseCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Application'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Institution Name')),
            TextField(controller: courseCtrl, decoration: const InputDecoration(labelText: 'Course')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      await _api.addAdmission(leadId: widget.leadId, institutionName: nameCtrl.text.trim(), courseName: courseCtrl.text.trim());
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.insights, size: 18),
              label: const Text('View College Match Predictions'),
              onPressed: () => _showPredictions(context),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final apps = snapshot.data ?? [];
          if (apps.isEmpty) {
            return const Center(child: Text('No applications yet', style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            itemCount: apps.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = apps[i];
              return ListTile(
                title: Text(a['institution_name']),
                subtitle: Text('${a['course_name'] ?? ''} ${a['intake'] != null ? '• ${a['intake']}' : ''}'),
                trailing: DropdownButton<String>(
                  value: a['application_status'],
                  underline: const SizedBox.shrink(),
                  items: stages.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) async {
                    if (v != null) {
                      await _api.updateAdmissionStatus(a['id'], v);
                      _refresh();
                    }
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

  Future<void> _showPredictions(BuildContext context) async {
    final data = await _api.getCollegePredictions(widget.leadId);
    final predictions = (data['predictions'] as List? ?? []).cast<Map<String, dynamic>>();
    final note = data['note'] as String?;
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('College Match Predictions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('Based on this consultancy\'s own past admission outcomes', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              if (note != null) Text(note, style: const TextStyle(color: Colors.grey)),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: predictions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = predictions[i];
                    final rate = p['historical_offer_rate_percent'];
                    return ListTile(
                      title: Text(p['college_name']),
                      subtitle: Text('${p['country'] ?? ''} • ${p['confidence']} confidence • ${p['past_offers']} offers, ${p['past_rejections']} rejections'),
                      trailing: rate != null
                          ? CircleAvatar(
                              backgroundColor: rate >= 60 ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                              child: Text('$rate%', style: TextStyle(fontSize: 11, color: rate >= 60 ? Colors.green : Colors.orange)),
                            )
                          : const Text('No data', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeesTab extends StatefulWidget {
  final String leadId;
  const _FeesTab({required this.leadId});

  @override
  State<_FeesTab> createState() => _FeesTabState();
}

class _FeesTabState extends State<_FeesTab> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getFees(widget.leadId);
  }

  void _refresh() => setState(() => _future = _api.getFees(widget.leadId));

  Future<void> _showCheckStatusPrompt(BuildContext context, String linkId) async {
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Waiting for payment'),
        content: const Text('Once the lead completes payment on Khalti, tap "Check Status" to confirm and mark this fee paid.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          FilledButton(
            onPressed: () async {
              final status = await _api.verifyKhaltiPayment(linkId);
              if (!context.mounted) return;
              Navigator.pop(context);
              if (status['verified'] == true) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment confirmed!')));
                _refresh();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Not paid yet — status: ${status['status']}')));
              }
            },
            child: const Text('Check Status'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendPaymentLink(BuildContext context, String feePaymentId) async {
    final gateway = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose Payment Gateway'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'razorpay'), child: const Text('Razorpay (India)')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'esewa'), child: const Text('eSewa (Nepal)')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'khalti'), child: const Text('Khalti (Nepal)')),
        ],
      ),
    );
    if (gateway == null || !context.mounted) return;

    try {
      final result = await _api.initiatePayment(feePaymentId: feePaymentId, gateway: gateway);
      if (!context.mounted) return;

      if (gateway == 'khalti' && result['payment_url'] != null) {
        await launchUrl(Uri.parse(result['payment_url']), mode: LaunchMode.externalApplication);
        if (context.mounted) _showCheckStatusPrompt(context, result['link_id']);
      } else {
        // eSewa (signed form POST) and Razorpay (Checkout.js config) don't
        // reduce to a single tappable URL — show what was generated so
        // the counselor knows it's configured and working, ready for the
        // checkout widget to be wired in.
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('$gateway payment created'),
            content: SingleChildScrollView(child: Text(result.toString())),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _addDialog() async {
    final typeCtrl = TextEditingController(text: 'Consultancy Fee');
    final amountCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Fee/Installment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Fee Type')),
            TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    final amount = double.tryParse(amountCtrl.text.trim());
    if (saved == true && typeCtrl.text.trim().isNotEmpty && amount != null) {
      await _api.addFee(leadId: widget.leadId, feeType: typeCtrl.text.trim(), amount: amount);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final fees = snapshot.data ?? [];
          if (fees.isEmpty) {
            return const Center(child: Text('No fee records yet', style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            itemCount: fees.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final f = fees[i];
              final paid = f['status'] == 'paid';
              return ListTile(
                title: Text(f['fee_type']),
                subtitle: Text('₹${f['amount']} ${f['due_date'] != null ? '• due ${f['due_date']}' : ''}'),
                trailing: paid
                    ? const Chip(label: Text('Paid'), backgroundColor: Color(0x1A4CAF50))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.payments_outlined, size: 20),
                            tooltip: 'Send payment link',
                            onPressed: () => _sendPaymentLink(context, f['id']),
                          ),
                          TextButton(
                            onPressed: () async {
                              await _api.markFeePaid(f['id']);
                              _refresh();
                            },
                            child: const Text('Mark Paid'),
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
