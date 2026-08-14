import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/appearance_settings.dart';

/// Team management. Was previously read-only — you could see who was on the
/// team but not add a counselor, change what they can do, or remove someone
/// who left, which made it unusable for an actual multi-person consultancy.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  static const _roles = ['admin', 'counselor', 'viewer'];
  static const _roleDescriptions = {
    'admin': 'Full access, including team and settings',
    'counselor': 'Works leads day to day',
    'viewer': 'Read-only access to leads and reports',
  };

  @override
  void initState() {
    super.initState();
    _future = _api.getTeam();
  }

  void _refresh() => setState(() => _future = _api.getTeam());

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg.replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _addMemberDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String role = 'counselor';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add team member'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full name')),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (they log in with this)'),
                ),
                TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Temporary password',
                    helperText: 'Share this with them — at least 8 characters',
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Role', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ..._roles.map((r) => RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: r,
                      groupValue: role,
                      title: Text(r[0].toUpperCase() + r.substring(1)),
                      subtitle: Text(_roleDescriptions[r]!, style: const TextStyle(fontSize: 11)),
                      onChanged: (v) => setDialogState(() => role = v ?? 'counselor'),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    if (nameCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty || passCtrl.text.length < 8) {
      _snack('Name, email and an 8+ character temporary password are all required');
      return;
    }
    try {
      await _api.addTeamMember(
        email: emailCtrl.text.trim(),
        fullName: nameCtrl.text.trim(),
        role: role,
        tempPassword: passCtrl.text,
      );
      _refresh();
      _snack('${nameCtrl.text.trim()} added — share their temporary password so they can log in');
    } catch (e) {
      _snack('Could not add: $e');
    }
  }

  Future<void> _changeRole(Map<String, dynamic> member) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Role for ${member['full_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ..._roles.map((r) => ListTile(
                  title: Text(r[0].toUpperCase() + r.substring(1)),
                  subtitle: Text(_roleDescriptions[r]!, style: const TextStyle(fontSize: 11)),
                  trailing: member['role'] == r ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(ctx, r),
                )),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == member['role']) return;
    try {
      await _api.updateTeamMember(member['id'], {'role': chosen});
      _refresh();
    } catch (e) {
      _snack('Could not change role: $e');
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> member) async {
    final isActive = member['active'] == true;
    if (isActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Deactivate ${member['full_name']}?'),
          content: const Text(
            'They will no longer be able to log in. Their name stays on every lead, call and note they worked on, '
            'so nothing in your history is lost. You can reactivate them later.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Deactivate')),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await _api.deactivateTeamMember(member['id']);
        _refresh();
      } catch (e) {
        _snack('Could not deactivate: $e');
      }
    } else {
      try {
        await _api.updateTeamMember(member['id'], {'active': true});
        _refresh();
      } catch (e) {
        _snack('Could not reactivate: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppearanceSettings>();
    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load the team: ${snapshot.error}'));
          }
          final team = snapshot.data ?? [];
          if (team.isEmpty) {
            return const Center(child: Text('No team members yet', style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            itemCount: team.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = team[i];
              final active = m['active'] == true;
              final name = (m['full_name'] as String?) ?? '?';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: active ? null : theme.mutedColor.withValues(alpha: 0.2),
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
                ),
                title: Text(
                  name,
                  style: TextStyle(
                    decoration: active ? null : TextDecoration.lineThrough,
                    color: active ? null : theme.mutedColor,
                  ),
                ),
                subtitle: Text(
                  active ? (m['email'] as String? ?? '') : '${m['email'] ?? ''} • deactivated',
                  style: TextStyle(fontSize: 12, color: active ? null : theme.mutedColor),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ActionChip(
                      label: Text(m['role'] ?? 'counselor', style: const TextStyle(fontSize: 11)),
                      onPressed: active ? () => _changeRole(m) : null,
                    ),
                    IconButton(
                      icon: Icon(active ? Icons.person_remove_outlined : Icons.person_add_alt_1),
                      tooltip: active ? 'Deactivate' : 'Reactivate',
                      color: active ? theme.dangerColor : theme.successColor,
                      onPressed: () => _toggleActive(m),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMemberDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Add member'),
      ),
    );
  }
}
