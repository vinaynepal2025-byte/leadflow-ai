import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import 'review_providers_screen.dart';

class MeetingsScreen extends StatefulWidget {
  final String leadId;
  final String? leadName;
  final String? leadPhone;
  const MeetingsScreen({super.key, required this.leadId, this.leadName, this.leadPhone});

  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  static const types = ['Counseling', 'Virtual Campus Tour', 'Physical Campus Visit', 'Parent Meeting', 'Demo Class', 'Other'];
  static const statuses = ['scheduled', 'completed', 'no-show', 'cancelled', 'rescheduled'];
  static const virtualPlatforms = ['WhatsApp Video', 'Google Meet', 'Zoom', 'Other'];
  // Intake sessions are named the way Indian/Nepali admission cycles
  // actually run, not as generic quarters.
  static const admissionSessions = ['2026 Spring', '2026 Fall', '2027 Spring', '2027 Fall', 'Undecided'];
  static const visitorRelations = ['Student alone', 'With parent(s)', 'With guardian', 'With sibling', 'With agent', 'Other'];
  static const referralSources = ['Walk-in', 'Alumni referral', 'Existing student', 'Agent/Partner', 'Social media', 'Website', 'Newspaper/Ad', 'Friend/Family'];
  static const areaOptions = [
    ('Campus', Icons.apartment_outlined),
    ('Hospital', Icons.local_hospital_outlined),
    ('Hostel', Icons.house_outlined),
    ('Faculty', Icons.person_outline),
    ('Fee Office', Icons.currency_rupee),
    ('Playground', Icons.sports_soccer_outlined),
    ('Admin', Icons.badge_outlined),
    ('Examination', Icons.edit_note_outlined),
    ('Library', Icons.menu_book_outlined),
    ('Labs', Icons.science_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _future = _api.getMeetings(leadId: widget.leadId);
  }

  void _refresh() => setState(() => _future = _api.getMeetings(leadId: widget.leadId));

  /// One consistent section header for the visit form — the old form was a
  /// flat run of controls with no grouping, which is what made it hard to
  /// scan on a phone.
  static Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF5B6478), letterSpacing: 0.6),
      );

  // -------------------- Rich Add Visit dialog --------------------

  Future<void> _addVisitDialog() async {
    final screenContext = context;
    bool isPhysical = true;
    final titleCtrl = TextEditingController();
    final campusCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    final callerCityCtrl = TextEditingController();
    final callerStateCtrl = TextEditingController();
    final queriesCtrl = TextEditingController();
    final referredByCtrl = TextEditingController();
    String platform = virtualPlatforms.first;
    bool firstTimeVisit = true;
    final Set<String> areasSelected = {};
    DateTime? picked = DateTime.now();
    XFile? photo;
    bool generatingLink = false;
    bool saving = false;
    // Intake details the schema already supported but the form never
    // captured — the things a counselor genuinely needs on a campus visit.
    String? admissionSession;
    String? visitorRelation;
    int visitsToNepal = 0;
    DateTime? followUpDate;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> takePhoto(ImageSource source) async {
            final picker = ImagePicker();
            final result = await picker.pickImage(source: source, imageQuality: 80);
            if (result != null) setSheetState(() => photo = result);
          }

          Future<void> generateLink() async {
            if (platform != 'WhatsApp Video') {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('$platform links must be created in the $platform app, then pasted here.'),
              ));
              return;
            }
            if (widget.leadPhone == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No phone number on file for this lead')),
              );
              return;
            }
            setSheetState(() => generatingLink = true);
            try {
              final link = await _api.getWhatsAppChatLink(
                widget.leadId,
                'Hi ${widget.leadName ?? 'there'}, join our video call here — tap the video icon once the chat opens.',
              );
              setSheetState(() => linkCtrl.text = link);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate link: $e')));
              }
            } finally {
              setSheetState(() => generatingLink = false);
            }
          }

          Future<void> save() async {
            if (titleCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title is required')));
              return;
            }
            setSheetState(() => saving = true);
            try {
              final meetingType = isPhysical ? 'Physical Campus Visit' : 'Virtual Campus Tour';
              final meeting = await _api.createMeeting(
                leadId: widget.leadId,
                meetingType: meetingType,
                title: titleCtrl.text.trim(),
                scheduledAt: (picked ?? DateTime.now()).toIso8601String(),
                mode: isPhysical ? 'in-person' : 'online',
                meetingLink: !isPhysical && linkCtrl.text.trim().isNotEmpty ? linkCtrl.text.trim() : null,
                campusName: campusCtrl.text.trim().isEmpty ? null : campusCtrl.text.trim(),
                hostName: 'Counselor',
              );

              await _api.updateMeetingVisitDetails(meeting['id'], {
                if (!isPhysical) 'virtual_platform': platform,
                if (areasSelected.isNotEmpty) 'areas_visited': areasSelected.toList(),
                if (!isPhysical && callerCityCtrl.text.trim().isNotEmpty) 'caller_city': callerCityCtrl.text.trim(),
                if (!isPhysical && callerStateCtrl.text.trim().isNotEmpty) 'caller_state': callerStateCtrl.text.trim(),
                if (queriesCtrl.text.trim().isNotEmpty) 'visitor_queries': queriesCtrl.text.trim(),
                'first_time_visit': firstTimeVisit,
                if (referredByCtrl.text.trim().isNotEmpty) 'referred_by': referredByCtrl.text.trim(),
                if (admissionSession != null) 'admission_session': admissionSession,
                if (visitorRelation != null) 'visitor_relation': visitorRelation,
                if (!firstTimeVisit || visitsToNepal > 0) 'visits_to_nepal_count': visitsToNepal,
                if (followUpDate != null) 'follow_up_date': followUpDate!.toIso8601String(),
              });

              bool photoFailed = false;
              if (photo != null) {
                try {
                  await _api.uploadDocument(
                    leadId: widget.leadId,
                    docType: 'visit_photo',
                    filePath: photo!.path,
                    fileName: photo!.name,
                    uploadedBy: 'Counselor',
                  );
                } catch (_) {
                  // Visit itself is already saved -- a photo-upload hiccup
                  // shouldn't lose the whole visit record, but the
                  // counselor needs to know the photo didn't make it in.
                  photoFailed = true;
                }
              }

              if (context.mounted) Navigator.pop(context);
              if (photoFailed && mounted) {
                ScaffoldMessenger.of(screenContext).showSnackBar(
                  const SnackBar(content: Text('Visit saved, but the photo failed to upload -- try attaching it again from Documents.')),
                );
              }
              _refresh();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save visit: $e')));
              }
            } finally {
              setSheetState(() => saving = false);
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.add_location_alt_outlined),
                      const SizedBox(width: 8),
                      const Text('Add Visit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _sectionLabel('Visit Mode'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('🏫 Physical'),
                          selected: isPhysical,
                          onSelected: (_) => setSheetState(() => isPhysical = true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('🎥 Virtual'),
                          selected: !isPhysical,
                          onSelected: (_) => setSheetState(() => isPhysical = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title *', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(picked == null ? 'Pick date & time' : picked.toString().substring(0, 16)),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context, initialDate: DateTime.now(),
                        firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date == null || !context.mounted) return;
                      final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                      if (time == null) return;
                      setSheetState(() => picked = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                    },
                  ),
                  const SizedBox(height: 10),

                  if (isPhysical) ...[
                    TextField(controller: campusCtrl, decoration: const InputDecoration(labelText: 'Campus / Location', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                  ] else ...[
                    _sectionLabel('Virtual Platform'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: virtualPlatforms.map((p) => ChoiceChip(
                        label: Text(p),
                        selected: platform == p,
                        onSelected: (_) => setSheetState(() => platform = p),
                      )).toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(controller: linkCtrl, decoration: const InputDecoration(labelText: 'Meeting link', border: OutlineInputBorder())),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: generatingLink ? null : generateLink,
                          icon: generatingLink
                              ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.auto_awesome, size: 16),
                          label: const Text('Generate'),
                        ),
                      ],
                    ),
                    if (platform == 'WhatsApp Video')
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Opens the WhatsApp chat with the lead — tap the video icon there to start the call.',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: callerCityCtrl, decoration: const InputDecoration(labelText: 'Caller City', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: callerStateCtrl, decoration: const InputDecoration(labelText: 'Caller State/Country', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  const SizedBox(height: 12),

                  _sectionLabel('Who came in'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: visitorRelations.map((r) => ChoiceChip(
                      label: Text(r, style: const TextStyle(fontSize: 12)),
                      selected: visitorRelation == r,
                      onSelected: (_) => setSheetState(() => visitorRelation = r),
                    )).toList(),
                  ),
                  const SizedBox(height: 12),

                  _sectionLabel('How they found us'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: referralSources.map((r) => ChoiceChip(
                      label: Text(r, style: const TextStyle(fontSize: 12)),
                      selected: referredByCtrl.text == r,
                      onSelected: (_) => setSheetState(() => referredByCtrl.text = r),
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: referredByCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Referred by (name, if any)',
                      helperText: 'Tap a source above, or type the exact person who referred them',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: 12),

                  _sectionLabel('Target intake'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: admissionSessions.map((s) => ChoiceChip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      selected: admissionSession == s,
                      onSelected: (_) => setSheetState(() => admissionSession = s),
                    )).toList(),
                  ),
                  const SizedBox(height: 12),

                  _sectionLabel('Areas of Interest / Visited (select all that apply)'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: areaOptions.map((a) {
                      final selected = areasSelected.contains(a.$1);
                      return FilterChip(
                        avatar: Icon(a.$2, size: 16),
                        label: Text(a.$1),
                        selected: selected,
                        onSelected: (v) => setSheetState(() => v ? areasSelected.add(a.$1) : areasSelected.remove(a.$1)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  _sectionLabel('Visit history'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: ChoiceChip(
                        label: const Text('First-time visit'),
                        selected: firstTimeVisit,
                        onSelected: (_) => setSheetState(() {
                          firstTimeVisit = true;
                          visitsToNepal = 0;
                        }),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: ChoiceChip(
                        label: const Text('Return visit'),
                        selected: !firstTimeVisit,
                        onSelected: (_) => setSheetState(() {
                          firstTimeVisit = false;
                          if (visitsToNepal < 1) visitsToNepal = 1;
                        }),
                      )),
                    ],
                  ),
                  if (!firstTimeVisit) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(child: Text('Previous visits', style: TextStyle(fontSize: 13))),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: visitsToNepal > 1 ? () => setSheetState(() => visitsToNepal--) : null,
                        ),
                        Text('$visitsToNepal', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setSheetState(() => visitsToNepal++),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),

                  _sectionLabel('Follow-up'),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_repeat_outlined, size: 16),
                    label: Text(followUpDate == null
                        ? 'Set a follow-up date (creates a reminder)'
                        : 'Follow up on ${followUpDate.toString().substring(0, 10)}'),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 3)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) setSheetState(() => followUpDate = date);
                    },
                  ),
                  const SizedBox(height: 12),

                  _sectionLabel('Photo (auto-added to report)'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      OutlinedButton.icon(icon: const Icon(Icons.camera_alt_outlined, size: 16), label: const Text('Camera'), onPressed: () => takePhoto(ImageSource.camera)),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(icon: const Icon(Icons.photo_library_outlined, size: 16), label: const Text('Gallery'), onPressed: () => takePhoto(ImageSource.gallery)),
                      const SizedBox(width: 8),
                      if (photo != null) const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    ],
                  ),
                  const SizedBox(height: 12),

                  TextField(controller: queriesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Visitor Queries', border: OutlineInputBorder())),
                  const SizedBox(height: 16),

                  FilledButton.icon(
                    onPressed: saving ? null : save,
                    icon: saving ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
                    label: Text(saving ? 'Saving...' : 'Save Visit'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _recordOutcome(Map<String, dynamic> meeting) async {
    String status = 'completed';
    final notesCtrl = TextEditingController();
    String interest = 'warm';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record Outcome'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setDialogState(() => status = v ?? status),
              ),
              if (status == 'completed')
                DropdownButtonFormField<String>(
                  value: interest,
                  decoration: const InputDecoration(labelText: 'Interest level'),
                  items: const ['hot', 'warm', 'cold'].map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
                  onChanged: (v) => setDialogState(() => interest = v ?? interest),
                ),
              TextField(controller: notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Outcome notes')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved == true) {
      await _api.updateMeeting(meeting['id'], {
        'status': status,
        'outcome_notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        if (status == 'completed') 'interest_level': interest,
      });
      _refresh();
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed': return Colors.green;
      case 'no-show': return Colors.red;
      case 'cancelled': return Colors.grey;
      default: return Colors.blue;
    }
  }

  IconData _typeIcon(String type) {
    if (type.contains('Campus')) return Icons.school;
    if (type == 'Parent Meeting') return Icons.family_restroom;
    if (type == 'Demo Class') return Icons.play_lesson;
    if (type == 'Peer Review Call') return Icons.star_outline;
    return Icons.groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meetings & Campus Tours'),
        actions: [
          IconButton(
            icon: const Icon(Icons.star_outline),
            tooltip: 'Book a Paid Peer Review',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ReviewProvidersScreen(leadId: widget.leadId, leadPhone: widget.leadPhone, leadName: widget.leadName)),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final meetings = snapshot.data ?? [];
          if (meetings.isEmpty) {
            return const Center(child: Text('No visits scheduled yet', style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            itemCount: meetings.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = meetings[i];
              final areas = (m['areas_visited'] is List) ? (m['areas_visited'] as List).join(', ') : null;
              return ListTile(
                leading: Icon(_typeIcon(m['meeting_type']), color: _statusColor(m['status'])),
                title: Text(m['title']),
                subtitle: Text(
                  '${m['meeting_type']} • ${m['scheduled_at']}\n'
                  'Status: ${m['status']}${m['interest_level'] != null ? ' • ${m['interest_level']}' : ''}'
                  '${areas != null && areas.isNotEmpty ? '\nVisited: $areas' : ''}',
                ),
                isThreeLine: true,
                trailing: m['status'] == 'scheduled'
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (m['meeting_link'] != null)
                            IconButton(
                              icon: const Icon(Icons.videocam, size: 20),
                              onPressed: () => launchUrl(Uri.parse(m['meeting_link']), mode: LaunchMode.externalApplication),
                            ),
                          TextButton(onPressed: () => _recordOutcome(m), child: const Text('Outcome', style: TextStyle(fontSize: 11))),
                        ],
                      )
                    : null,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addVisitDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Visit'),
      ),
    );
  }
}
