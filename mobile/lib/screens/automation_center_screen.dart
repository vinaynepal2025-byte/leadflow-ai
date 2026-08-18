import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/lead.dart';

/// Automation Center -- Leads Ecosystem redesign, Phase 6. The mobile
/// entry point for everything Phases 3-6 built on the backend: the
/// MANUAL/AUTO mode toggle, running any of the 10 AI agents against a
/// specific lead, and the orchestrator's job queue (pending/awaiting
/// approval/dead-lettered).
///
/// [initialLeadId]/[initialLeadName] let lead_detail_screen.dart deep-link
/// straight into "run an agent for THIS lead" instead of making the user
/// search for it again.
class AutomationCenterScreen extends StatefulWidget {
  final String? initialLeadId;
  final String? initialLeadName;
  const AutomationCenterScreen({super.key, this.initialLeadId, this.initialLeadName});

  @override
  State<AutomationCenterScreen> createState() => _AutomationCenterScreenState();
}

class _AutomationCenterScreenState extends State<AutomationCenterScreen> {
  final _api = ApiService();

  Map<String, dynamic>? _settings;
  bool _settingsLoading = true;
  List<Map<String, dynamic>> _agents = [];
  bool _agentsLoading = true;

  // Defaults to 'pending' rather than 'awaiting_approval' -- every
  // built-in tool today is LOW/MEDIUM risk (see builtinTools.js), so
  // requires_approval never becomes true for anything the 10 agents
  // currently do. Landing on "Needs Approval" first would show "Nothing
  // here right now" for every tenant, every time, which reads as broken
  // even though it's technically correct.
  String _jobStatusFilter = 'pending';
  late Future<List<Map<String, dynamic>>> _jobsFuture;

  static const _jobStatusFilters = ['pending', 'awaiting_approval', 'dead_letter', 'succeeded'];
  static const _jobStatusLabels = {
    'awaiting_approval': 'Needs Approval',
    'pending': 'Pending',
    'dead_letter': 'Failed (Dead Letter)',
    'succeeded': 'Succeeded',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAgents();
    _jobsFuture = _api.getOrchestratorJobs(status: _jobStatusFilter);
  }

  Future<void> _loadSettings() async {
    try {
      final s = await _api.getSettings();
      if (mounted) setState(() { _settings = s; _settingsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _settingsLoading = false);
    }
  }

  Future<void> _loadAgents() async {
    try {
      final a = await _api.getAgents();
      if (mounted) setState(() { _agents = a; _agentsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _agentsLoading = false);
    }
  }

  void _refreshJobs() => setState(() => _jobsFuture = _api.getOrchestratorJobs(status: _jobStatusFilter));

  Future<void> _confirmModeChange(String newMode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(newMode == 'auto' ? 'Turn on Auto Mode?' : 'Switch to Manual Mode?'),
        content: Text(newMode == 'auto'
            ? 'Every 15 minutes, all 10 AI agents will scan your leads and act on their own '
              '(recommendations are enqueued automatically instead of waiting for you to tap Run).\n\n'
              'What this can do: create internal reminders/notifications, and change a lead\'s '
              'pipeline status (e.g. New → Qualified).\n\n'
              'What it will NEVER do: send a WhatsApp message, email, or call a lead -- none of the '
              'agents are allowed to contact a lead directly. You can switch back to Manual any time.'
            : 'AI agents will only act when you explicitly tap "Run" on a specific lead. Nothing runs on its own.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(newMode == 'auto' ? 'Turn On' : 'Switch')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _api.updateSettings({'automation_mode': newMode});
      if (mounted) setState(() => _settings = {..._settings ?? {}, 'automation_mode': newMode});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update mode: $e')));
    }
  }

  Future<void> _pickLeadAndRunAgent(String agentName, String agentLabel) async {
    if (widget.initialLeadId != null) {
      await _runAgentForLead(agentName, agentLabel, widget.initialLeadId!, widget.initialLeadName ?? 'this lead');
      return;
    }

    final searchCtrl = TextEditingController();
    List<Lead> results = [];
    bool searching = false;

    final picked = await showModalBottomSheet<Lead>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> doSearch(String q) async {
            setSheetState(() => searching = true);
            try {
              final all = await _api.getLeads();
              final ql = q.trim().toLowerCase();
              final filtered = ql.isEmpty
                  ? all.take(20).toList()
                  : all.where((l) => l.fullName.toLowerCase().contains(ql) || (l.phone ?? '').contains(ql)).take(20).toList();
              setSheetState(() { results = filtered; searching = false; });
            } catch (_) {
              setSheetState(() => searching = false);
            }
          }

          if (results.isEmpty && !searching && searchCtrl.text.isEmpty) {
            doSearch('');
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Search leads by name or phone',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: doSearch,
                    ),
                  ),
                  if (searching) const LinearProgressIndicator(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final l = results[i];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(l.fullName),
                          subtitle: Text(l.phone ?? l.email ?? l.stage),
                          onTap: () => Navigator.pop(context, l),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (picked != null) {
      await _runAgentForLead(agentName, agentLabel, picked.id, picked.fullName);
    }
  }

  Future<void> _runAgentForLead(String agentName, String agentLabel, String leadId, String leadName) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    Map<String, dynamic>? analysis;
    String? error;
    try {
      analysis = await _api.analyzeAgent(agentName, leadId);
    } catch (e) {
      error = e.toString();
    }
    if (mounted) Navigator.pop(context); // close the spinner
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Analysis failed: $error')));
      return;
    }

    final result = analysis!;
    final recommendedAction = result['recommended_action'] as Map<String, dynamic>?;
    final situation = result['situation']?.toString();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$agentLabel · $leadName'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (situation != null) Text(situation.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (recommendedAction != null) ...[
                const Text('Recommended action:', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 4),
                Text(_describeAction(recommendedAction)),
              ] else
                const Text('No action needed right now.', style: TextStyle(color: Colors.grey)),
              if (result['suggested_message'] != null) ...[
                const SizedBox(height: 12),
                const Text('AI-suggested message (for you to review, never auto-sent):', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 4),
                Text('"${result['suggested_message']['message_draft'] ?? ''}"', style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          if (recommendedAction != null)
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await _api.actAgent(agentName, leadId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Action enqueued -- it will run within a few minutes.')),
                    );
                    _refreshJobs();
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not enqueue: $e')));
                }
              },
              child: const Text('Approve & Run'),
            ),
        ],
      ),
    );
  }

  String _describeAction(Map<String, dynamic> action) {
    final toolName = action['tool_name']?.toString() ?? '';
    final input = action['tool_input'] as Map<String, dynamic>? ?? {};
    switch (toolName) {
      case 'reminder.create':
        return 'Create reminder: "${input['title'] ?? ''}"';
      case 'notification.create':
        return 'Notify team: "${input['title'] ?? ''}"';
      case 'lead.update_lifecycle_status':
        return 'Move lead to status: ${input['to_status'] ?? ''}';
      default:
        return toolName;
    }
  }

  Future<void> _approveJob(String id) async {
    try {
      await _api.approveOrchestratorJob(id);
      _refreshJobs();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not approve: $e')));
    }
  }

  Future<void> _retryJob(String id) async {
    try {
      await _api.retryOrchestratorJob(id);
      _refreshJobs();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not retry: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = _settings?['automation_mode']?.toString() ?? 'manual';

    return Scaffold(
      appBar: AppBar(title: const Text('Automation Center')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _modeCard(mode),
          const SizedBox(height: 24),
          Text('AI Agents', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_agentsLoading) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else Card(
            child: Column(
              children: _agents.map((a) {
                final name = a['name']?.toString() ?? '';
                final label = name.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
                return ListTile(
                  leading: const Icon(Icons.smart_toy_outlined, color: Colors.deepPurple),
                  title: Text(label),
                  subtitle: Text(a['description']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: FilledButton.tonal(
                    onPressed: () => _pickLeadAndRunAgent(name, label),
                    child: const Text('Run'),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
          Text('Job Queue', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _jobStatusFilters.map((s) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_jobStatusLabels[s] ?? s),
                  selected: _jobStatusFilter == s,
                  onSelected: (_) => setState(() { _jobStatusFilter = s; _refreshJobs(); }),
                ),
              )).toList(),
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _jobsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              }
              final jobs = snapshot.data ?? [];
              if (jobs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Nothing here right now.', style: TextStyle(color: Colors.grey))),
                );
              }
              return Card(
                child: Column(
                  children: jobs.map((j) {
                    final toolName = j['tool_name']?.toString() ?? '';
                    Map<String, dynamic> input = {};
                    try { input = jsonDecodeMap(j['tool_input_json']); } catch (_) {}
                    return ListTile(
                      leading: Icon(_iconForStatus(j['status']?.toString() ?? ''), color: _colorForStatus(j['status']?.toString() ?? '')),
                      title: Text(_describeAction({'tool_name': toolName, 'tool_input': input})),
                      subtitle: Text('${j['initiated_by'] ?? ''} · ${j['status'] ?? ''}${j['last_error'] != null ? '\n${j['last_error']}' : ''}'),
                      isThreeLine: j['last_error'] != null,
                      trailing: j['status'] == 'awaiting_approval'
                          ? FilledButton.tonal(onPressed: () => _approveJob(j['id']), child: const Text('Approve'))
                          : j['status'] == 'dead_letter'
                              ? OutlinedButton(onPressed: () => _retryJob(j['id']), child: const Text('Retry'))
                              : null,
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _modeCard(String mode) {
    final isAuto = mode == 'auto';
    return Card(
      color: isAuto ? Colors.green.withValues(alpha: 0.08) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(isAuto ? Icons.autorenew : Icons.pan_tool_alt_outlined, color: isAuto ? Colors.green : Colors.grey.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isAuto ? 'Auto Mode' : 'Manual Mode', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    isAuto
                        ? 'AI agents scan and act on leads automatically every 15 minutes.'
                        : 'AI agents only act when you tap Run below.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (_settingsLoading)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Switch(value: isAuto, onChanged: (v) => _confirmModeChange(v ? 'auto' : 'manual')),
          ],
        ),
      ),
    );
  }

  IconData _iconForStatus(String status) {
    switch (status) {
      case 'succeeded': return Icons.check_circle_outline;
      case 'awaiting_approval': return Icons.pending_actions_outlined;
      case 'dead_letter': return Icons.error_outline;
      case 'running': return Icons.autorenew;
      default: return Icons.schedule_outlined;
    }
  }

  Color _colorForStatus(String status) {
    switch (status) {
      case 'succeeded': return Colors.green;
      case 'awaiting_approval': return Colors.orange;
      case 'dead_letter': return Colors.red;
      default: return Colors.blueGrey;
    }
  }
}

/// tool_input_json comes back from the backend as a JSON-encoded string
/// (see routes/orchestrator.js's GET /jobs -- it returns the raw
/// automation_jobs row, which stores tool_input as TEXT). Decoded
/// defensively since a malformed/empty value should degrade to an empty
/// map, not crash the Job Queue list.
Map<String, dynamic> jsonDecodeMap(dynamic raw) {
  if (raw == null) return {};
  if (raw is Map<String, dynamic>) return raw;
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
  }
  return {};
}
