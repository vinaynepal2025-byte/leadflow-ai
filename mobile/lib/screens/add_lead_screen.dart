import 'package:flutter/material.dart';
import '../services/api_service.dart';

const List<Map<String, String>> kCountryCodes = [
  {'code': '+91', 'flag': '🇮🇳', 'name': 'India'},
  {'code': '+977', 'flag': '🇳🇵', 'name': 'Nepal'},
  {'code': '+1', 'flag': '🇺🇸', 'name': 'USA/Canada'},
  {'code': '+44', 'flag': '🇬🇧', 'name': 'UK'},
  {'code': '+61', 'flag': '🇦🇺', 'name': 'Australia'},
  {'code': '+64', 'flag': '🇳🇿', 'name': 'New Zealand'},
  {'code': '+971', 'flag': '🇦🇪', 'name': 'UAE'},
  {'code': '+966', 'flag': '🇸🇦', 'name': 'Saudi Arabia'},
  {'code': '+65', 'flag': '🇸🇬', 'name': 'Singapore'},
  {'code': '+49', 'flag': '🇩🇪', 'name': 'Germany'},
  {'code': '+33', 'flag': '🇫🇷', 'name': 'France'},
  {'code': '+880', 'flag': '🇧🇩', 'name': 'Bangladesh'},
  {'code': '+94', 'flag': '🇱🇰', 'name': 'Sri Lanka'},
  {'code': '+92', 'flag': '🇵🇰', 'name': 'Pakistan'},
];

class AddLeadScreen extends StatefulWidget {
  const AddLeadScreen({super.key});

  @override
  State<AddLeadScreen> createState() => _AddLeadScreenState();
}

class _AddLeadScreenState extends State<AddLeadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _parentNameCtrl = TextEditingController();
  final _parentPhoneCtrl = TextEditingController();
  String _source = 'Website';
  String _countryCode = '+91';
  bool _saving = false;

  static const sources = ['Website', 'Walk-in', 'Referral', 'Facebook Ad', 'Instagram', 'Other'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    _parentNameCtrl.dispose();
    _parentPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final duplicates = await _api.checkDuplicateLead(fullName: _nameCtrl.text.trim(), phone: _phoneCtrl.text.trim());
    if (duplicates.isNotEmpty && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Possible duplicate'),
          content: Text('This looks similar to an existing lead: "${duplicates.first['full_name']}" '
              '(${duplicates.first['reasons'].join(', ')}). Save anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save Anyway')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    try {
      await _api.createLead(
        fullName: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        phoneCountryCode: _phoneCtrl.text.trim().isEmpty ? null : _countryCode,
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        source: _source,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        parentName: _parentNameCtrl.text.trim().isEmpty ? null : _parentNameCtrl.text.trim(),
        parentPhone: _parentPhoneCtrl.text.trim().isEmpty ? null : _parentPhoneCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save lead: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Lead')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String>(
                    initialValue: _countryCode,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: kCountryCodes.map((c) => DropdownMenuItem(
                      value: c['code'],
                      child: Text('${c['flag']} ${c['code']}', overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (v) => setState(() => _countryCode = v ?? _countryCode),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _source,
              decoration: const InputDecoration(labelText: 'Source', border: OutlineInputBorder()),
              items: sources.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _source = v ?? _source),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            const Text('Parent/Guardian (optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _parentNameCtrl,
              decoration: const InputDecoration(labelText: 'Parent Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _parentPhoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Parent Phone', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Lead'),
            ),
          ],
        ),
      ),
    );
  }
}
