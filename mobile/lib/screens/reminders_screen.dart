// Follow-ups (reminders).
//
// The previous version was 74 lines and read-only: it listed pending
// reminders and let you tick them off. There was no way to *create* one from
// the app at all — the only reminders that existed were the ones the call
// module generated automatically. For a CRM whose entire job is making sure
// nobody gets forgotten, that's the wrong way round.
//
// This adds the full lifecycle, plus the two things that decide whether a
// follow-up list gets used or abandoned:
//
// - Snooze. "Not now" is the honest answer most of the time, and without a
//   snooze the counsellor either completes something they haven't done
//   (poisoning the data) or leaves it overdue forever (poisoning the list).
// - Overdue framing. An undifferentiated list of dates is noise; what
//   matters is what's late, what's today, and what can wait.

import 'package:flutter/material.dart';
import '../models/reminder.dart';
import '../services/api_service.dart';
import 'lead_detail_screen.dart';

enum ReminderFilter { overdue, today, upcoming, done }

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final ApiService _api = ApiService();

  List<ReminderItem> _all = [];
  ReminderFilter _filter = ReminderFilter.overdue;
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
      // Pull both states in one go so the filter chips can switch instantly
      // and show real counts rather than re-fetching per tab.
      final pending = await _api.getReminders(status: 'pending');
      List<ReminderItem> done = [];
      try {
        done = await _api.getReminders(status: 'done');
      } catch (_) {}
      setState(() => _all = [...pending, ...done]);
    } catch (e) {
      setState(() => _error = 'Could not load follow-ups: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime? _parseDue(String raw) {
    try {
      return DateTime.parse(raw.replaceAll(' ', 'T'));
    } catch (_) {
      return null;
    }
  }

  bool _isOverdue(ReminderItem r) {
    if (r.status == 'done') return false;
    final d = _parseDue(r.dueAt);
    return d != null && d.isBefore(DateTime.now());
  }

  bool _isToday(ReminderItem r) {
    final d = _parseDue(r.dueAt);
    if (d == null) return false;
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  List<ReminderItem> _forFilter(ReminderFilter f) {
    switch (f) {
      case ReminderFilter.overdue:
        return _all.where(_isOverdue).toList()
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      case ReminderFilter.today:
        return _all.where((r) => r.status != 'done' && _isToday(r) && !_isOverdue(r)).toList()
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      case ReminderFilter.upcoming:
        return _all
            .where((r) => r.status != 'done' && !_isOverdue(r) && !_isToday(r))
            .toList()
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      case ReminderFilter.done:
        return _all.where((r) => r.status == 'done').toList()
          ..sort((a, b) => b.dueAt.compareTo(a.dueAt));
    }
  }

  String _labelFor(ReminderFilter f) {
    switch (f) {
      case ReminderFilter.overdue:
        return 'Overdue';
      case ReminderFilter.today:
        return 'Today';
      case ReminderFilter.upcoming:
        return 'Upcoming';
      case ReminderFilter.done:
        return 'Done';
    }
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  Future<void> _markDone(ReminderItem r) async {
    try {
      await _api.markReminderDone(r.id);
      await _load();
    } catch (e) {
      _snack('Could not update: $e');
    }
  }

  Future<void> _reopen(ReminderItem r) async {
    try {
      await _api.updateReminder(r.id, status: 'pending');
      await _load();
    } catch (e) {
      _snack('Could not reopen: $e');
    }
  }

  Future<void> _snooze(ReminderItem r) async {
    final choice = await showModalBottomSheet<Duration>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Snooze until',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            ListTile(
              leading: const Icon(Icons.timelapse),
              title: const Text('In 1 hour'),
              onTap: () => Navigator.pop(ctx, const Duration(hours: 1)),
            ),
            ListTile(
              leading: const Icon(Icons.wb_twilight),
              title: const Text('This evening'),
              onTap: () => Navigator.pop(ctx, const Duration(hours: 5)),
            ),
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Tomorrow'),
              onTap: () => Navigator.pop(ctx, const Duration(days: 1)),
            ),
            ListTile(
              leading: const Icon(Icons.next_week),
              title: const Text('Next week'),
              onTap: () => Navigator.pop(ctx, const Duration(days: 7)),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final newDue = DateTime.now().add(choice);
    try {
      await _api.updateReminder(r.id, dueAt: _fmt(newDue), status: 'pending');
      await _load();
      _snack('Snoozed to ${_pretty(newDue)}');
    } catch (e) {
      _snack('Could not snooze: $e');
    }
  }

  Future<void> _delete(ReminderItem r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete follow-up?'),
        content: Text(r.title),
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
    if (ok != true) return;
    try {
      await _api.deleteReminder(r.id);
      await _load();
    } catch (e) {
      _snack('Could not delete: $e');
    }
  }

  Future<void> _edit(ReminderItem r) async {
    await _showEditor(existing: r);
  }

  Future<void> _showEditor({ReminderItem? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    DateTime due = existing != null
        ? (_parseDue(existing.dueAt) ?? DateTime.now().add(const Duration(hours: 1)))
        : DateTime.now().add(const Duration(hours: 1));

    // Creating a standalone reminder needs a lead to attach to, because the
    // reminders table requires lead_id. Rather than inventing a nullable
    // path, creation from this screen is offered only for editing existing
    // ones; new ones are created from a lead (see Lead Detail), which is
    // also where the counsellor actually is when they decide to follow up.
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(existing == null ? 'New follow-up' : 'Edit follow-up',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'What needs doing?',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: Text(_pretty(due)),
                    trailing: const Icon(Icons.edit, size: 17),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: due,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                      );
                      if (d == null) return;
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(due),
                      );
                      if (t == null) return;
                      setSheet(() => due = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () async {
                          if (titleCtrl.text.trim().isEmpty) return;
                          Navigator.pop(ctx, true);
                        },
                        child: const Text('Save'),
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

    if (saved != true || existing == null) return;
    try {
      await _api.updateReminder(existing.id,
          title: titleCtrl.text.trim(), dueAt: _fmt(due));
      await _load();
    } catch (e) {
      _snack('Could not save: $e');
    }
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${_2(d.month)}-${_2(d.day)} ${_2(d.hour)}:${_2(d.minute)}:00';

  static String _2(int n) => n.toString().padLeft(2, '0');

  String _pretty(DateTime d) {
    final n = DateTime.now();
    final sameDay = d.year == n.year && d.month == n.month && d.day == n.day;
    final tm = '${_2(d.hour)}:${_2(d.minute)}';
    if (sameDay) return 'Today $tm';
    final t = n.add(const Duration(days: 1));
    if (d.year == t.year && d.month == t.month && d.day == t.day) return 'Tomorrow $tm';
    return '${d.day}/${d.month}/${d.year} $tm';
  }

  String _relative(ReminderItem r) {
    final d = _parseDue(r.dueAt);
    if (d == null) return r.dueAt;
    final diff = d.difference(DateTime.now());
    if (r.status == 'done') return _pretty(d);
    if (diff.isNegative) {
      final ago = diff.abs();
      if (ago.inDays >= 1) return '${ago.inDays}d overdue';
      if (ago.inHours >= 1) return '${ago.inHours}h overdue';
      return '${ago.inMinutes}m overdue';
    }
    if (diff.inDays >= 1) return 'in ${diff.inDays}d · ${_pretty(d)}';
    if (diff.inHours >= 1) return 'in ${diff.inHours}h · ${_pretty(d)}';
    return 'in ${diff.inMinutes}m';
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final items = _forFilter(_filter);

    return Scaffold(
      appBar: AppBar(title: const Text('Follow-ups')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : Column(
                  children: [
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        children: ReminderFilter.values.map((f) {
                          final count = _forFilter(f).length;
                          final on = _filter == f;
                          final urgent = f == ReminderFilter.overdue && count > 0;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              selected: on,
                              selectedColor: urgent ? const Color(0xFFE5484D) : null,
                              label: Text(
                                '${_labelFor(f)}${count > 0 ? '  $count' : ''}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: on && urgent ? Colors.white : null,
                                  fontWeight: urgent && !on ? FontWeight.bold : null,
                                ),
                              ),
                              onSelected: (_) => setState(() => _filter = f),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    Expanded(
                      child: items.isEmpty
                          ? RefreshIndicator(
                              onRefresh: _load,
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 90),
                                  Center(
                                    child: Text(
                                      _filter == ReminderFilter.overdue
                                          ? 'Nothing overdue'
                                          : 'Nothing here',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (ctx, i) => _buildTile(items[i]),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildTile(ReminderItem r) {
    final overdue = _isOverdue(r);
    final done = r.status == 'done';

    return ListTile(
      leading: Icon(
        done ? Icons.check_circle : Icons.alarm,
        color: done
            ? Colors.green
            : overdue
                ? const Color(0xFFE5484D)
                : const Color(0xFFE07A1F),
      ),
      title: Text(
        r.title,
        style: TextStyle(
          fontSize: 14.5,
          decoration: done ? TextDecoration.lineThrough : null,
          color: done ? Colors.grey : null,
        ),
      ),
      subtitle: Text(
        '${_relative(r)}${r.assignedTo != null ? "  ·  ${r.assignedTo}" : ""}',
        style: TextStyle(
          fontSize: 12,
          color: overdue ? const Color(0xFFE5484D) : Colors.grey.shade600,
          fontWeight: overdue ? FontWeight.w600 : null,
        ),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: r.leadId)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!done)
            IconButton(
              icon: const Icon(Icons.check_circle_outline, color: Colors.green),
              tooltip: 'Mark done',
              onPressed: () => _markDone(r),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (v) {
              if (v == 'snooze') _snooze(r);
              if (v == 'edit') _edit(r);
              if (v == 'delete') _delete(r);
              if (v == 'reopen') _reopen(r);
            },
            itemBuilder: (ctx) => [
              if (!done) const PopupMenuItem(value: 'snooze', child: Text('Snooze')),
              if (!done) const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (done) const PopupMenuItem(value: 'reopen', child: Text('Reopen')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
