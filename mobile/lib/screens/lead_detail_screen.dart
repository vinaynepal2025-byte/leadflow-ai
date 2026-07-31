import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/lead.dart';
import '../models/communication.dart';
import '../services/api_service.dart';
import '../widgets/stage_chip.dart';
import 'documents_screen.dart';
import 'admissions_fees_screen.dart';
import 'email_compose_screen.dart';
import 'calls_voice_notes_screen.dart';
import 'meetings_screen.dart';
import 'journey_screen.dart';
import 'alumni_match_screen.dart';
import 'compliance_screen.dart';

class LeadDetailScreen extends StatefulWidget {
  final String leadId;
  const LeadDetailScreen({super.key, required this.leadId});

  @override
  State<LeadDetailScreen> createState() => _LeadDetailScreenState();
}

class _LeadDetailScreenState extends State<LeadDetailScreen> {
  final ApiService _api = ApiService();
  Lead? _lead;
  List<Communication> _comms = [];
  List<Map<String, dynamic>> _customFieldDefs = [];
  List<Map<String, dynamic>> _stages = [];
  bool _loading = true;
  AiInsight? _insight;
  bool _analyzing = false;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final lead = await _api.getLead(widget.leadId);
    final comms = await _api.getCommunications(widget.leadId);
    final defs = await _api.getCustomFieldDefinitions();
    final stages = await _api.getPipelineStages();
    if (!mounted) return;
    setState(() {
      _lead = lead;
      _comms = comms;
      _customFieldDefs = defs;
      _stages = stages;
      _loading = false;
    });
  }

  Future<void> _changeStage(String newStage) async {
    await _api.updateLeadStage(widget.leadId, newStage);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _lead == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final lead = _lead!;
    return Scaffold(
      appBar: AppBar(title: Text(lead.fullName)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                StageChip(stage: lead.stage),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: lead.stage,
                    items: _stages
                        .map((s) => DropdownMenuItem(value: s['name'] as String, child: Text('Move to ${s['name']}')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null && v != lead.stage) _changeStage(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (lead.phone != null) _infoRow(Icons.phone, lead.phone!),
            if (lead.email != null) _infoRow(Icons.email, lead.email!),
            if (lead.source != null) _infoRow(Icons.source, lead.source!),
            if (lead.notes != null && lead.notes!.isNotEmpty)
              _infoRow(Icons.notes, lead.notes!),
            if (lead.parentName != null)
              _infoRow(Icons.family_restroom, 'Guardian: ${lead.parentName}${lead.parentPhone != null ? " (${lead.parentPhone})" : ""}'),
            if (_customFieldDefs.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Custom Fields', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              ..._customFieldDefs.map((def) => _customFieldTile(lead, def)),
            ],
            const SizedBox(height: 20),
            _aiSection(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _whatsappButton(lead)),
                if (lead.email != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.email_outlined),
                      label: const Text('Email'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => EmailComposeScreen(lead: lead)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_outlined),
              label: const Text('Documents'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DocumentsScreen(leadId: lead.id)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.school_outlined),
              label: const Text('Admissions & Fees'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AdmissionsFeesScreen(leadId: lead.id)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.phone_in_talk_outlined),
              label: const Text('Calls & Voice Notes'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CallsVoiceNotesScreen(leadId: lead.id)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('Meetings & Campus Tours'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => MeetingsScreen(leadId: lead.id)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.flight_takeoff_outlined),
              label: const Text('Visa, Travel & Student'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => JourneyScreen(leadId: lead.id)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.diversity_3_outlined),
              label: const Text('Alumni Network'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AlumniMatchScreen(leadId: lead.id)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Consent & Compliance'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ComplianceScreen(leadId: lead.id, leadName: lead.fullName)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Communication History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (_comms.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No interactions logged yet', style: TextStyle(color: Colors.grey)),
              )
            else
              ..._comms.map(_commTile),
          ],
        ),
      ),
    );
  }

  Widget _customFieldTile(Lead lead, Map<String, dynamic> def) {
    final key = def['field_key'] as String;
    final currentValue = lead.customFields[key];

    if (def['field_type'] == 'select') {
      final options = (def['options'] as List?)?.cast<String>() ?? [];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DropdownButtonFormField<String>(
          value: options.contains(currentValue) ? currentValue as String : null,
          decoration: InputDecoration(labelText: def['label'], isDense: true, border: const OutlineInputBorder()),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) async {
            if (v != null) await _api.setLeadCustomField(lead.id, key, v);
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        value: currentValue?.toString() ?? '',
        keyboardType: def['field_type'] == 'number' ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: def['label'], isDense: true, border: const OutlineInputBorder()),
        onFieldSubmitted: (v) async => await _api.setLeadCustomField(lead.id, key, v),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _commTile(Communication c) {
    final inbound = c.direction == 'inbound';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          inbound ? Icons.call_received : Icons.call_made,
          color: inbound ? Colors.green : Colors.blue,
        ),
        title: Text(c.body ?? '(no text)'),
        subtitle: Text('${c.channel} • ${c.createdAt}${c.createdBy != null ? ' • ${c.createdBy}' : ''}'),
        dense: true,
      ),
    );
  }

  Widget _whatsappButton(Lead lead) {
    if (lead.phone == null) return const SizedBox.shrink();
    return OutlinedButton.icon(
      icon: const Icon(Icons.chat, color: Colors.green),
      label: const Text('Send WhatsApp (free)'),
      onPressed: () async {
        final link = await _api.getWhatsAppChatLink(
          lead.id,
          'Hi ${lead.fullName}, following up on your enquiry.',
        );
        await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
        await _api.confirmWhatsAppSent(
          lead.id,
          'Hi ${lead.fullName}, following up on your enquiry.',
          'Counselor',
        );
        _load();
      },
    );
  }

  Widget _aiSection() {
    return Card(
      color: Colors.deepPurple.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.deepPurple, size: 20),
                const SizedBox(width: 8),
                const Text('AI Insight', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: _analyzing ? null : _runAnalysis,
                  child: Text(_analyzing ? 'Analyzing...' : 'Analyze'),
                ),
              ],
            ),
            if (_aiError != null)
              Text(_aiError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            if (_insight != null) ...[
              const SizedBox(height: 6),
              Text(_insight!.summary),
              const SizedBox(height: 6),
              Text('Sentiment: ${_insight!.sentiment} • Intent: ${_insight!.buyingIntent}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Text('Next step: ${_insight!.suggestedNextAction}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runAnalysis() async {
    setState(() {
      _analyzing = true;
      _aiError = null;
    });
    try {
      final insight = await _api.analyzeLead(widget.leadId);
      setState(() => _insight = insight);
    } catch (e) {
      setState(() => _aiError = e.toString());
    } finally {
      setState(() => _analyzing = false);
    }
  }
}
