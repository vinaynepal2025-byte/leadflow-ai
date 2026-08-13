// Call Log tab.
//
// The problem this replaces: logging a call was a five-field dialog nobody
// filled in, the screen dead-ended with "No phone number on file" and no way
// to add one, and a mis-logged outcome was permanent. Calls are the highest
// frequency action in an admissions consultancy, so friction here compounds
// faster than anywhere else in the product.
//
// The design bets, in order of importance:
//
// 1. Log at the moment of truth. The counsellor hangs up and comes straight
//    back into the app; that's when the outcome is fresh and the tap is
//    cheap. We watch the lifecycle, and if we're resumed after having
//    launched the dialer, we ask once, with the call duration already
//    measured. One tap and it's logged.
// 2. One tap, not five fields. Outcome is a chip. Notes are optional and
//    come after. Duration is measured, not typed.
// 3. Never dead-end. No phone number is a prompt to add one inline, not a
//    greyed-out button and an apology.
// 4. Be honest about thin data. Connect rate off two calls is noise; the
//    best-time badge only appears once there's enough history to mean
//    something (the backend enforces this and says so plainly).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';

/// Outcome vocabulary. Kept in underscore form to match
/// backend/routes/calls.js, which keys its auto-follow-up rules off these
/// exact strings — an earlier version of this screen used hyphens, which
/// silently meant no follow-up reminder was ever created.
class CallOutcome {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final bool connected;

  const CallOutcome(this.key, this.label, this.icon, this.color, this.connected);
}

const List<CallOutcome> kCallOutcomes = [
  CallOutcome('connected', 'Connected', Icons.check_circle, Color(0xFF2FB344), true),
  CallOutcome('interested', 'Interested', Icons.star, Color(0xFF1E9E6A), true),
  CallOutcome('callback_requested', 'Call back later', Icons.schedule, Color(0xFFE8A33D), true),
  CallOutcome('no_answer', 'No answer', Icons.call_missed, Color(0xFFE07A1F), false),
  CallOutcome('busy', 'Busy', Icons.phone_paused, Color(0xFFE07A1F), false),
  CallOutcome('switched_off', 'Switched off', Icons.phonelink_erase, Color(0xFF9AA0A6), false),
  CallOutcome('not_reachable', 'Not reachable', Icons.signal_cellular_off, Color(0xFF9AA0A6), false),
  CallOutcome('wrong_number', 'Wrong number', Icons.report_gmailerrorred, Color(0xFFE5484D), false),
  CallOutcome('not_interested', 'Not interested', Icons.thumb_down_alt_outlined, Color(0xFFE5484D), true),
];

CallOutcome outcomeFor(String? key) {
  for (final o in kCallOutcomes) {
    if (o.key == key) return o;
  }
  // Tolerate legacy hyphenated values written by older builds so old rows
  // still render with a sensible icon instead of falling off the list.
  final normalised = (key ?? '').replaceAll('-', '_');
  for (final o in kCallOutcomes) {
    if (o.key == normalised) return o;
  }
  return CallOutcome(key ?? 'unknown', key ?? 'Unknown', Icons.call, const Color(0xFF5F6368), false);
}

class CallLogTab extends StatefulWidget {
  final String leadId;
  final String? leadPhone;
  final String? leadName;

  const CallLogTab({
    super.key,
    required this.leadId,
    this.leadPhone,
    this.leadName,
  });

  @override
  State<CallLogTab> createState() => _CallLogTabState();
}

class _CallLogTabState extends State<CallLogTab> with WidgetsBindingObserver {
  final ApiService _api = ApiService();

  List<Map<String, dynamic>> _calls = [];
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _bestTime;
  bool _loading = true;
  String? _error;
  String? _phone;

  // Set when we hand off to the dialer, so returning to the app can offer
  // to log the call with a real measured duration.
  DateTime? _callStartedAt;
  bool _awaitingLogPrompt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _phone = widget.leadPhone;
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingLogPrompt) {
      _awaitingLogPrompt = false;
      final started = _callStartedAt;
      _callStartedAt = null;
      if (started == null) return;
      final elapsed = DateTime.now().difference(started).inSeconds;
      // Under ~5 seconds almost certainly means the dialer was opened and
      // dismissed, not an actual call — don't nag in that case.
      if (elapsed < 5) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showOutcomeSheet(prefilledDuration: elapsed);
      });
    }
  }

  bool get _hasPhone => _phone != null && _phone!.trim().isNotEmpty;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final calls = await _api.getCalls(widget.leadId);
      setState(() => _calls = calls);
      // Stats and best-time are supporting context, not the main content —
      // if either fails the call list should still render.
      try {
        final stats = await _api.getCallStats(widget.leadId);
        if (mounted) setState(() => _stats = stats);
      } catch (_) {}
      try {
        final best = await _api.getBestTimeToCall(widget.leadId);
        if (mounted) setState(() => _bestTime = best);
      } catch (_) {}
    } catch (e) {
      setState(() => _error = 'Could not load calls: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------------
  // Placing calls
  // ------------------------------------------------------------------

  Future<void> _callPhone() async {
    if (!_hasPhone) return;
    _callStartedAt = DateTime.now();
    _awaitingLogPrompt = true;
    try {
      final ok = await launchUrl(Uri(scheme: 'tel', path: _phone));
      if (!ok) {
        _awaitingLogPrompt = false;
        _snack('Could not open the dialer on this device');
      }
    } catch (e) {
      _awaitingLogPrompt = false;
      _snack('Could not open the dialer: $e');
    }
  }

  Future<void> _callWhatsApp() async {
    if (!_hasPhone) return;
    _callStartedAt = DateTime.now();
    _awaitingLogPrompt = true;
    try {
      final message =
          'Hi ${widget.leadName ?? "there"}, calling regarding your enquiry — tap the voice or video icon once the chat opens.';
      final link = await _api.getWhatsAppChatLink(widget.leadId, message);
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      await _api.confirmWhatsAppSent(widget.leadId, message, 'Counselor');
    } catch (e) {
      _awaitingLogPrompt = false;
      _snack('Could not open WhatsApp: $e');
    }
  }

  Future<void> _addPhoneInline() async {
    final controller = TextEditingController(text: _phone ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add phone number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '9876543210',
            helperText: 'Saved to this lead',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    try {
      await _api.updateLead(widget.leadId, {'phone': result});
      setState(() => _phone = result);
      _snack('Phone number saved');
    } catch (e) {
      _snack('Could not save number: $e');
    }
  }

  // ------------------------------------------------------------------
  // Logging
  // ------------------------------------------------------------------

  Future<void> _showOutcomeSheet({int? prefilledDuration, Map<String, dynamic>? editing}) async {
    final notesCtrl = TextEditingController(text: editing?['notes']?.toString() ?? '');
    String? selected = editing?['outcome']?.toString();
    int? duration = prefilledDuration ?? (editing?['duration_seconds'] as num?)?.toInt();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    editing != null
                        ? 'Edit call'
                        : (prefilledDuration != null ? 'How did the call go?' : 'Log a call'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  if (duration != null && duration! > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Duration ${_formatDuration(duration!)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kCallOutcomes.map((o) {
                      final isSel = selected == o.key;
                      return ChoiceChip(
                        selected: isSel,
                        avatar: Icon(o.icon, size: 16, color: isSel ? Colors.white : o.color),
                        label: Text(o.label),
                        selectedColor: o.color,
                        labelStyle: TextStyle(
                          color: isSel ? Colors.white : null,
                          fontSize: 13,
                        ),
                        onSelected: (_) => setSheetState(() => selected = o.key),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    minLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                      hintText: 'What did they say?',
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (selected != null && _autoFollowUpLabel(selected!) != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.alarm, size: 15, color: Color(0xFF4C6FFF)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'A follow-up reminder will be created ${_autoFollowUpLabel(selected!)}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF4C6FFF)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Not now'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: selected == null
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _saveCall(
                                  outcome: selected!,
                                  notes: notesCtrl.text.trim(),
                                  durationSeconds: duration,
                                  editingId: editing?['id']?.toString(),
                                );
                              },
                        child: Text(editing != null ? 'Update' : 'Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _autoFollowUpLabel(String outcome) {
    // Mirrors AUTO_FOLLOWUP_HOURS in backend/routes/calls.js. Shown so the
    // counsellor knows a reminder is coming without having to discover it.
    switch (outcome) {
      case 'no_answer':
        return 'in 4 hours';
      case 'busy':
        return 'in 2 hours';
      case 'switched_off':
      case 'callback_requested':
        return 'tomorrow';
      default:
        return null;
    }
  }

  Future<void> _saveCall({
    required String outcome,
    String? notes,
    int? durationSeconds,
    String? editingId,
  }) async {
    try {
      if (editingId != null) {
        await _api.updateCall(
          editingId,
          outcome: outcome,
          notes: notes?.isEmpty == true ? null : notes,
          durationSeconds: durationSeconds,
        );
        _snack('Call updated');
      } else {
        await _api.logCall(
          leadId: widget.leadId,
          outcome: outcome,
          notes: notes?.isEmpty == true ? null : notes,
          calledBy: 'Counselor',
          durationSeconds: durationSeconds,
          phoneUsed: _phone,
        );
        _snack('Call logged');
      }
      await _load();
    } catch (e) {
      _snack('Could not save: $e');
    }
  }

  Future<void> _deleteCall(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this call log?'),
        content: const Text('Any follow-up reminder it created will be cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.deleteCall(id);
      await _load();
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  // ------------------------------------------------------------------
  // AI call prep
  // ------------------------------------------------------------------

  Future<void> _prepareCall() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Expanded(child: Text('Preparing your call…')),
          ],
        ),
      ),
    );
    Map<String, dynamic>? prep;
    String? err;
    try {
      prep = await _api.prepareCall(widget.leadId);
    } catch (e) {
      err = e.toString();
    }
    if (!mounted) return;
    Navigator.pop(context); // close loader
    if (prep == null) {
      _snack('Could not prepare call: $err');
      return;
    }
    _showPrepSheet(prep);
  }

  void _showPrepSheet(Map<String, dynamic> prep) {
    final talkingPoints = (prep['talking_points'] as List?) ?? [];
    final objections = (prep['likely_objections'] as List?) ?? [];
    final avoid = (prep['avoid'] as List?) ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF4C6FFF)),
                    const SizedBox(width: 8),
                    Text('Call prep · ${prep['lead_name'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    _prepBlock('Objective', [prep['objective']?.toString() ?? ''],
                        Icons.flag_outlined, const Color(0xFF4C6FFF)),
                    _prepBlock('Open with', [prep['opening_line']?.toString() ?? ''],
                        Icons.record_voice_over_outlined, const Color(0xFF2FB344)),
                    if (talkingPoints.isNotEmpty)
                      _prepBlock('Talking points',
                          talkingPoints.map((e) => e.toString()).toList(),
                          Icons.checklist, const Color(0xFF5F6368)),
                    if (objections.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('If they say…',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      ...objections.whereType<Map>().map((o) {
                        final m = Map<String, dynamic>.from(o);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('"${m['objection'] ?? ''}"',
                                    style: const TextStyle(
                                        fontStyle: FontStyle.italic, fontSize: 13)),
                                const SizedBox(height: 6),
                                Text(m['response']?.toString() ?? '',
                                    style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                    if (avoid.isNotEmpty)
                      _prepBlock('Avoid', avoid.map((e) => e.toString()).toList(),
                          Icons.do_not_disturb_on_outlined, const Color(0xFFE5484D)),
                    const SizedBox(height: 8),
                    Text(
                      'AI-generated from this lead\'s history. Check anything factual before saying it.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('Call now'),
                    onPressed: _hasPhone
                        ? () {
                            Navigator.pop(ctx);
                            _callPhone();
                          }
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _prepBlock(String title, List<String> lines, IconData icon, Color color) {
    final visible = lines.where((l) => l.trim().isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          ...visible.map((l) => Padding(
                padding: const EdgeInsets.only(left: 21, bottom: 3),
                child: Text(visible.length > 1 ? '• $l' : l,
                    style: const TextStyle(fontSize: 13.5)),
              )),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  _buildActionRow(),
                  if (!_hasPhone) _buildNoPhoneCard(),
                  if (_stats != null) _buildStatsCard(),
                  if (_bestTime != null && _bestTime!['best_hour'] != null) _buildBestTimeCard(),
                  const Divider(height: 24),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    )
                  else if (_calls.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.call_end_outlined, size: 42, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            const Text('No calls logged yet',
                                style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text('Tap Phone Call above — we\'ll ask how it went afterwards.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._calls.map(_buildCallTile),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showOutcomeSheet(),
        icon: const Icon(Icons.add_call),
        label: const Text('Log call'),
      ),
    );
  }

  Widget _buildActionRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Phone Call'),
                  onPressed: _hasPhone ? _callPhone : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                  icon: const Icon(Icons.chat, size: 18),
                  label: const Text('WhatsApp'),
                  onPressed: _hasPhone ? _callWhatsApp : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 17),
              label: const Text('Prep me for this call'),
              onPressed: _prepareCall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoPhoneCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        color: const Color(0xFFFFF4E5),
        child: ListTile(
          leading: const Icon(Icons.phone_missed, color: Color(0xFFE07A1F)),
          title: const Text('No phone number on file', style: TextStyle(fontSize: 14)),
          subtitle: const Text('Add one to call or WhatsApp this lead',
              style: TextStyle(fontSize: 12)),
          trailing: TextButton(onPressed: _addPhoneInline, child: const Text('Add')),
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    final s = _stats!;
    final total = s['total_attempts'] ?? 0;
    if (total == 0) return const SizedBox.shrink();
    final rate = s['connect_rate'];
    final avg = s['avg_talk_seconds'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('$total', 'Attempts'),
              _stat(rate == null ? '—' : '$rate%', 'Connected'),
              _stat(avg == null ? '—' : _formatDuration(avg as int), 'Avg talk'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildBestTimeCard() {
    final b = _bestTime!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        color: const Color(0xFFEAF1FF),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.schedule, color: Color(0xFF4C6FFF), size: 20),
          title: Text('Best time to call: ${b['best_hour_label'] ?? ''}',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle: Text(b['message']?.toString() ?? '',
              style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }

  Widget _buildCallTile(Map<String, dynamic> c) {
    final o = outcomeFor(c['outcome']?.toString());
    final duration = (c['duration_seconds'] as num?)?.toInt();
    final followUp = c['follow_up_at']?.toString();
    final notes = c['notes']?.toString();

    final subtitleParts = <String>[];
    if (c['created_at'] != null) subtitleParts.add(c['created_at'].toString());
    if (duration != null && duration > 0) subtitleParts.add(_formatDuration(duration));
    if (c['called_by'] != null) subtitleParts.add(c['called_by'].toString());

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: o.color.withOpacity(0.15),
        child: Icon(o.icon, color: o.color, size: 19),
      ),
      title: Text(o.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitleParts.join('  ·  '),
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          if (notes != null && notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(notes, style: const TextStyle(fontSize: 13)),
            ),
          if (followUp != null && followUp.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  const Icon(Icons.alarm, size: 12, color: Color(0xFF4C6FFF)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Follow-up $followUp',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF4C6FFF))),
                  ),
                ],
              ),
            ),
        ],
      ),
      isThreeLine: notes != null && notes.isNotEmpty,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (v) {
          if (v == 'edit') _showOutcomeSheet(editing: c);
          if (v == 'delete') _deleteCall(c['id'].toString());
        },
        itemBuilder: (ctx) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
