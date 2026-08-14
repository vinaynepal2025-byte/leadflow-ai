import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'lead_detail_screen.dart';

class WorkQueueScreen extends StatefulWidget {
  const WorkQueueScreen({super.key});

  @override
  State<WorkQueueScreen> createState() => _WorkQueueScreenState();
}

class _WorkQueueScreenState extends State<WorkQueueScreen> {
  final _api = ApiService();
  late Future<Map<String, dynamic>> _future;
  // Separate Future, deliberately not awaited together with _future --
  // the deterministic queue should render immediately; the AI briefing
  // card fills in independently once its one Gemini call returns.
  late Future<Map<String, dynamic>> _briefingFuture;

  @override
  void initState() {
    super.initState();
    _future = _api.getScoringToday();
    _briefingFuture = _api.getWorkQueueBriefing();
  }

  void _refresh() => setState(() {
        _future = _api.getScoringToday();
        _briefingFuture = _api.getWorkQueueBriefing();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Work Queue")),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = snapshot.data ?? {};
            final summary = d['summary'] as Map<String, dynamic>? ?? {};
            final priority = (d['priority_calls'] as List? ?? []).cast<Map<String, dynamic>>();
            final atRisk = (d['at_risk'] as List? ?? []).cast<Map<String, dynamic>>();
            final untouched = (d['never_contacted'] as List? ?? []).cast<Map<String, dynamic>>();
            final unreachable = (d['unreachable'] as List? ?? []).cast<Map<String, dynamic>>();
            final unassigned = (d['unassigned'] as List? ?? []).cast<Map<String, dynamic>>();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _briefingCard(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _summaryChip('🔥 ${summary['hot'] ?? 0}', 'Hot', Colors.red),
                    const SizedBox(width: 8),
                    _summaryChip('🌤 ${summary['warm'] ?? 0}', 'Warm', Colors.orange),
                    const SizedBox(width: 8),
                    _summaryChip('❄ ${summary['cold'] ?? 0}', 'Cold', Colors.blueGrey),
                  ],
                ),
                const SizedBox(height: 20),
                if (priority.isNotEmpty) ...[
                  const Text('🔥 Priority Calls', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...priority.map((l) => _leadTile(l, Colors.red)),
                  const SizedBox(height: 20),
                ],
                if (atRisk.isNotEmpty) ...[
                  const Text('⚠️ At Risk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...atRisk.map((l) => _leadTile(l, Colors.orange)),
                  const SizedBox(height: 20),
                ],
                // AI Suggestion Layer v1 additions -- these two were
                // previously invisible: leadScoring.js already tracked
                // missing phone/parent contact as a scoring signal, but
                // that only ever quietly lowered a lead's rank. Nothing
                // told a counselor "this lead literally cannot be
                // called" or "this lead belongs to no one" until now.
                if (unreachable.isNotEmpty) ...[
                  const Text('📵 Unreachable — no contact info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...unreachable.map((l) => ListTile(
                        leading: const Icon(Icons.phone_disabled_outlined, color: Colors.redAccent),
                        title: Text(l['full_name']),
                        subtitle: const Text('No phone, email, or parent contact on file', style: TextStyle(fontSize: 12)),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: l['id']))),
                      )),
                  const SizedBox(height: 20),
                ],
                if (unassigned.isNotEmpty) ...[
                  const Text('🙋 Unassigned — nobody owns this', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...unassigned.map((l) => ListTile(
                        leading: const Icon(Icons.person_add_alt_outlined, color: Colors.deepPurple),
                        title: Text(l['full_name']),
                        subtitle: Text(l['stage'] ?? '', style: const TextStyle(fontSize: 12)),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: l['id']))),
                      )),
                  const SizedBox(height: 20),
                ],
                if (untouched.isNotEmpty) ...[
                  const Text('👻 Never Contacted', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...untouched.map((l) => ListTile(
                        leading: const Icon(Icons.person_off_outlined, color: Colors.grey),
                        title: Text(l['full_name']),
                        subtitle: Text('Added ${l['created_at']}'),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: l['id']))),
                      )),
                ],
                if (priority.isEmpty && atRisk.isEmpty && untouched.isEmpty && unreachable.isEmpty && unassigned.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: Text('All caught up! 🎉', style: TextStyle(color: Colors.grey))),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // AI Suggestion Layer v1 -- renders once the single Gemini call for
  // the whole queue returns. Own FutureBuilder, independent of the main
  // one above, so this card alone shows a loading state while the fast
  // deterministic lists below have already rendered.
  Widget _briefingCard() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _briefingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6D28D9), Color(0xFF1D4ED8)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 12),
                Text('Preparing today\'s briefing…', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          );
        }
        final b = snapshot.data;
        if (b == null || snapshot.hasError) return const SizedBox.shrink();
        final priorities = (b['priorities'] as List? ?? []).cast<String>();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF6D28D9), Color(0xFF1D4ED8)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text("Today's Briefing", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                b['headline'] as String? ?? '',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
              ),
              if ((b['narrative'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(b['narrative'] as String, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ],
              if (priorities.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...priorities.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Expanded(child: Text(p, style: const TextStyle(color: Colors.white, fontSize: 12.5))),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _summaryChip(String count, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(count, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _leadTile(Map<String, dynamic> l, Color accent) {
    final topReason = (l['signals'] as List?)?.isNotEmpty == true ? l['signals'][0]['reason'] : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.15),
          child: Text('${l['score']}', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        title: Text(l['full_name']),
        subtitle: topReason != null ? Text(topReason, style: const TextStyle(fontSize: 12)) : null,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: l['lead_id']))),
      ),
    );
  }
}
