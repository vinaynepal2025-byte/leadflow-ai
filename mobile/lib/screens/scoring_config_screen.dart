import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ScoringConfigScreen extends StatefulWidget {
  const ScoringConfigScreen({super.key});

  @override
  State<ScoringConfigScreen> createState() => _ScoringConfigScreenState();
}

class _ScoringConfigScreenState extends State<ScoringConfigScreen> {
  final _api = ApiService();
  late Future<Map<String, dynamic>> _future;
  final Map<String, num> _pendingChanges = {};
  Map<String, dynamic>? _previewResult;

  @override
  void initState() {
    super.initState();
    _future = _api.getScoringConfig();
  }

  void _refresh() {
    _pendingChanges.clear();
    _previewResult = null;
    setState(() => _future = _api.getScoringConfig());
  }

  Future<void> _runPreview() async {
    if (_pendingChanges.isEmpty) return;
    final result = await _api.previewScoringConfig(_pendingChanges);
    setState(() => _previewResult = result);
  }

  Future<void> _save() async {
    try {
      await _api.saveScoringConfig(_pendingChanges);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scoring rules saved')));
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lead Scoring Rules'),
        actions: [
          TextButton(
            onPressed: () async {
              await _api.resetScoringConfig();
              _refresh();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final weights = (data['weights'] as List).cast<Map<String, dynamic>>();
          final grouped = <String, List<Map<String, dynamic>>>{};
          for (final w in weights) {
            grouped.putIfAbsent(w['group'], () => []).add(w);
          }

          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Adjust how much each signal matters for your consultancy. Preview before saving to see who moves.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
              if (_previewResult != null) _previewCard(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: grouped.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ...entry.value.map((w) => _weightSlider(w)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (_pendingChanges.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: _runPreview, child: const Text('Preview Impact'))),
                      const SizedBox(width: 10),
                      Expanded(child: FilledButton(onPressed: _save, child: const Text('Save'))),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _weightSlider(Map<String, dynamic> w) {
    final currentValue = (_pendingChanges[w['key']] ?? w['value']).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(w['label'], style: const TextStyle(fontSize: 13))),
          Expanded(
            flex: 4,
            child: Slider(
              value: currentValue.clamp(-100, 100),
              min: -100, max: 100, divisions: 40,
              label: currentValue.round().toString(),
              onChanged: (v) => setState(() {
                _pendingChanges[w['key']] = v.round();
                _previewResult = null;
              }),
            ),
          ),
          SizedBox(width: 32, child: Text(currentValue.round().toString(), textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _previewCard() {
    final d = _previewResult!;
    final before = d['distribution_before'];
    final after = d['distribution_after'];
    final changes = (d['biggest_changes'] as List).cast<Map<String, dynamic>>();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${d['affected_count']} leads would move', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('🔥 ${before['hot']}→${after['hot']}  🌤 ${before['warm']}→${after['warm']}  ❄ ${before['cold']}→${after['cold']}'),
          const SizedBox(height: 6),
          ...changes.take(5).map((c) => Text(
                '${c['full_name']}: ${c['score_before']} → ${c['score_after']}',
                style: const TextStyle(fontSize: 12),
              )),
        ],
      ),
    );
  }
}
