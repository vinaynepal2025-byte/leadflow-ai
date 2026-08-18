// Lead activity timeline.
//
// Everything that has happened with a lead lives across nine tables, each on
// its own screen. That works for doing the next task, but not for the
// question a counsellor actually asks when they open a lead they haven't
// touched in three weeks: "what's the story here?"
//
// This is that story, newest first, in one scroll.

import 'package:flutter/material.dart';
import '../services/api_service.dart';

class LeadTimelineScreen extends StatefulWidget {
  final String leadId;
  final String? leadName;

  const LeadTimelineScreen({super.key, required this.leadId, this.leadName});

  @override
  State<LeadTimelineScreen> createState() => _LeadTimelineScreenState();
}

class _LeadTimelineScreenState extends State<LeadTimelineScreen> {
  final ApiService _api = ApiService();

  List<Map<String, dynamic>> _events = [];
  Set<String> _activeFilters = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getLeadTimeline(widget.leadId);
      final raw = (data['events'] as List?) ?? [];
      setState(() {
        _events = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      setState(() => _error = 'Could not load timeline: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const Map<String, _EventStyle> _styles = {
    'call': _EventStyle(Icons.phone, Color(0xFF2FB344)),
    'communication': _EventStyle(Icons.chat_bubble_outline, Color(0xFF25D366)),
    'voice_note': _EventStyle(Icons.mic_none, Color(0xFF9333EA)),
    'document': _EventStyle(Icons.description_outlined, Color(0xFF4C6FFF)),
    'meeting': _EventStyle(Icons.event_available_outlined, Color(0xFF0E7490)),
    'note': _EventStyle(Icons.sticky_note_2_outlined, Color(0xFFE8A33D)),
    'payment': _EventStyle(Icons.payments_outlined, Color(0xFF1E9E6A)),
    'offer': _EventStyle(Icons.local_offer_outlined, Color(0xFFB45309)),
    'reminder': _EventStyle(Icons.alarm, Color(0xFFE07A1F)),
    'created': _EventStyle(Icons.person_add_alt, Color(0xFF5F6368)),
    'lifecycle_change': _EventStyle(Icons.timeline, Color(0xFF7C3AED)),
  };

  // source: MANUAL/AI/AUTOMATION/SYSTEM -- Leads Ecosystem Phase 6. MANUAL
  // is the overwhelming default (every event before this phase), so it's
  // left unbadged; the other three are worth calling out since they're
  // the genuinely new thing this phase adds to the timeline.
  static const Map<String, Color> _sourceColors = {
    'AI': Color(0xFF9333EA),
    'AUTOMATION': Color(0xFFB8860B),
    'SYSTEM': Color(0xFF5F6368),
  };

  _EventStyle _styleFor(String type) =>
      _styles[type] ?? const _EventStyle(Icons.circle, Color(0xFF9AA0A6));

  List<Map<String, dynamic>> get _visible => _activeFilters.isEmpty
      ? _events
      : _events.where((e) => _activeFilters.contains(e['type'])).toList();

  /// Groups by calendar day so the feed reads as a diary rather than an
  /// undifferentiated wall of rows.
  Map<String, List<Map<String, dynamic>>> _grouped() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final e in _visible) {
      final at = e['at']?.toString() ?? '';
      final day = at.length >= 10 ? at.substring(0, 10) : 'Unknown';
      map.putIfAbsent(day, () => []).add(e);
    }
    return map;
  }

  String _dayLabel(String day) {
    final now = DateTime.now();
    final today = '${now.year}-${_2(now.month)}-${_2(now.day)}';
    final y = now.subtract(const Duration(days: 1));
    final yesterday = '${y.year}-${_2(y.month)}-${_2(y.day)}';
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    return day;
  }

  static String _2(int n) => n.toString().padLeft(2, '0');

  String _timeOf(String at) =>
      at.length >= 16 ? at.substring(11, 16) : '';

  @override
  Widget build(BuildContext context) {
    final types = _events.map((e) => e['type'].toString()).toSet().toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.leadName == null ? 'Activity' : 'Activity · ${widget.leadName}',
            overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : Column(
                  children: [
                    if (types.length > 1)
                      SizedBox(
                        height: 46,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          children: types.map((t) {
                            final on = _activeFilters.contains(t);
                            final s = _styleFor(t);
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                selected: on,
                                avatar: Icon(s.icon, size: 15, color: on ? Colors.white : s.color),
                                label: Text(t.replaceAll('_', ' '),
                                    style: TextStyle(fontSize: 12, color: on ? Colors.white : null)),
                                selectedColor: s.color,
                                onSelected: (_) => setState(() {
                                  if (on) {
                                    _activeFilters.remove(t);
                                  } else {
                                    _activeFilters.add(t);
                                  }
                                }),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    Expanded(
                      child: _visible.isEmpty
                          ? const Center(
                              child: Text('Nothing here yet', style: TextStyle(color: Colors.grey)))
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView(
                                padding: const EdgeInsets.only(bottom: 24),
                                children: _grouped().entries.expand((entry) {
                                  return [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                                      child: Text(
                                        _dayLabel(entry.key),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                    ...entry.value.map(_buildEvent),
                                  ];
                                }).toList(),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEvent(Map<String, dynamic> e) {
    final type = e['type']?.toString() ?? '';
    final s = _styleFor(type);
    final subtitle = e['subtitle']?.toString();
    final at = e['at']?.toString() ?? '';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Rail: dot plus connecting line, so the eye follows one thread
          // down the page instead of reading ten disconnected cards.
          SizedBox(
            width: 52,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: s.color.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(s.icon, size: 16, color: s.color),
                ),
                Expanded(
                  child: Container(width: 1.5, color: Colors.grey.shade300),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e['title']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                      if (_sourceColors.containsKey(e['source']))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _sourceColors[e['source']]!.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              e['source'].toString(),
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _sourceColors[e['source']]),
                            ),
                          ),
                        ),
                      Text(_timeOf(at),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(subtitle,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    ),
                  _buildMeta(e),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeta(Map<String, dynamic> e) {
    final meta = e['meta'];
    if (meta is! Map) return const SizedBox.shrink();
    final m = Map<String, dynamic>.from(meta);
    final bits = <String>[];

    if (m['duration_seconds'] != null) {
      final d = (m['duration_seconds'] as num).toInt();
      if (d > 0) bits.add(d < 60 ? '${d}s' : '${d ~/ 60}m ${d % 60}s');
    }
    if (m['by'] != null && m['by'].toString().isNotEmpty) bits.add(m['by'].toString());
    if (m['status'] != null) bits.add(m['status'].toString());

    if (bits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(bits.join('  ·  '),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
    );
  }
}

class _EventStyle {
  final IconData icon;
  final Color color;
  const _EventStyle(this.icon, this.color);
}
