import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

/// Browse verified review providers across all colleges, register a new
/// provider, and book a paid peer-review call. Portable pattern: payment
/// goes straight to the provider's own UPI ID via a device UPI-intent
/// link, so no payment-gateway approval is needed to go live.
class ReviewProvidersScreen extends StatefulWidget {
  final String leadId;
  const ReviewProvidersScreen({super.key, required this.leadId});

  @override
  State<ReviewProvidersScreen> createState() => _ReviewProvidersScreenState();
}

class _ReviewProvidersScreenState extends State<ReviewProvidersScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _collegesFuture;
  Map<String, dynamic>? _selectedCollege;
  Future<List<Map<String, dynamic>>>? _providersFuture;

  @override
  void initState() {
    super.initState();
    _collegesFuture = _api.getColleges();
  }

  void _selectCollege(Map<String, dynamic> college) {
    setState(() {
      _selectedCollege = college;
      _providersFuture = _api.getReviewProviders(collegeId: college['id']);
    });
  }

  Future<void> _registerDialog() async {
    if (_selectedCollege == null) return;
    final nameCtrl = TextEditingController();
    final roleCtrl = TextEditingController(text: 'student');
    final phoneCtrl = TextEditingController();
    final upiCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final bioCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Register as a Review Provider'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full name *')),
              TextField(controller: roleCtrl, decoration: const InputDecoration(labelText: 'Role (e.g. MBBS 3rd year)')),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
              TextField(controller: upiCtrl, decoration: const InputDecoration(labelText: 'UPI ID * (name@bank)')),
              TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price per review (₹)')),
              TextField(controller: bioCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Short bio')),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('A counselor must verify this registration before it appears to leads.',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Register')),
        ],
      ),
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty && upiCtrl.text.trim().isNotEmpty) {
      try {
        await _api.registerReviewProvider(
          collegeId: _selectedCollege!['id'],
          fullName: nameCtrl.text.trim(),
          role: roleCtrl.text.trim().isEmpty ? null : roleCtrl.text.trim(),
          phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
          upiId: upiCtrl.text.trim(),
          pricePerReview: double.tryParse(priceCtrl.text.trim()),
          bio: bioCtrl.text.trim().isEmpty ? null : bioCtrl.text.trim(),
        );
        if (mounted) {
          setState(() => _providersFuture = _api.getReviewProviders(collegeId: _selectedCollege!['id'], activeOnly: false));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registered — pending verification')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not register: $e')));
      }
    }
  }

  Future<void> _bookDialog(Map<String, dynamic> provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Book with ${provider['full_name']}'),
        content: Text(
          'Price: ₹${provider['price_per_review'] ?? _selectedCollege?['peer_review_default_price'] ?? '—'}\n\n'
          'A UPI payment link will open your phone\'s UPI app (GPay, PhonePe, Paytm, etc.) '
          'with the amount and provider pre-filled. Payment goes directly to the provider.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Book & Pay')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await _api.bookPeerReview(
        leadId: widget.leadId,
        collegeId: _selectedCollege!['id'],
        providerId: provider['id'],
      );
      final bookingId = result['booking']['id'] as String;
      final upiLink = result['upi_payment_link'] as String;

      if (!mounted) return;
      final paid = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Complete Payment'),
          content: const Text('Tap below to open your UPI app. Once payment is done, come back and confirm.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel Booking')),
            FilledButton.icon(
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: const Text('Open UPI App'),
              onPressed: () async {
                await launchUrl(Uri.parse(upiLink), mode: LaunchMode.externalApplication);
              },
            ),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("I've Paid")),
          ],
        ),
      );

      if (paid == true) {
        await _api.confirmPeerReviewPayment(bookingId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment confirmed — review call added to Meetings')),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paid Peer Reviews')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _collegesFuture,
              builder: (context, snapshot) {
                final colleges = (snapshot.data ?? []).where((c) => c['peer_review_enabled'] == true).toList();
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (colleges.isEmpty) {
                  return const Text(
                    'No colleges have peer review enabled yet. Turn it on from Colleges & Universities.',
                    style: TextStyle(color: Colors.grey),
                  );
                }
                return DropdownButtonFormField<Map<String, dynamic>>(
                  value: _selectedCollege,
                  decoration: const InputDecoration(labelText: 'College', border: OutlineInputBorder()),
                  items: colleges.map((c) => DropdownMenuItem(value: c, child: Text(c['name']))).toList(),
                  onChanged: (v) { if (v != null) _selectCollege(v); },
                );
              },
            ),
          ),
          if (_selectedCollege != null)
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _providersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final providers = snapshot.data ?? [];
                  if (providers.isEmpty) {
                    return const Center(child: Text('No providers yet for this college', style: TextStyle(color: Colors.grey)));
                  }
                  return ListView.separated(
                    itemCount: providers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final p = providers[i];
                      final rating = p['average_rating'];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                        title: Text(p['full_name']),
                        subtitle: Text(
                          '${p['role'] ?? ''}${rating != null ? ' • ⭐ $rating (${p['rating_count']})' : ''}\n'
                          '₹${p['price_per_review'] ?? _selectedCollege!['peer_review_default_price'] ?? '—'} per review',
                        ),
                        isThreeLine: true,
                        trailing: FilledButton(onPressed: () => _bookDialog(p), child: const Text('Book')),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
      floatingActionButton: _selectedCollege == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _registerDialog,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Register as Provider'),
            ),
    );
  }
}
