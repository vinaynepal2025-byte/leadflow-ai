// lib/screens/exam_home_screen.dart
//
// Report Cards / Exam Intelligence — smart dashboard landing screen.
//
// Deliberately its own independent section, not part of the Leads
// workflow: Leads is follow-up/sales-pipeline work on prospects; this is
// for already-enrolled students' exam results and report cards — a
// different job for a different screen, per the owner's explicit
// direction. Reached from the More menu like every other top-level
// section (see more_screen.dart's kMoreMenuDefaults), never from Lead
// Detail.
//
// Three things on this screen: (1) student-wise search — jump straight to
// any student's report card by name or roll/student code; (2) batch-wise
// stat tiles + one AI-written summary paragraph for a chosen batch; (3) the
// original list of imported exam sittings, unchanged.

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';
import 'exam_import_screen.dart';
import 'exam_cohort_screen.dart';
import 'exam_report_screen.dart';
import 'exam_template_editor_screen.dart';

class ExamHomeScreen extends StatefulWidget {
  const ExamHomeScreen({super.key});

  @override
  State<ExamHomeScreen> createState() => _ExamHomeScreenState();
}

class _ExamHomeScreenState extends State<ExamHomeScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _students = [];
  bool _loading = true;
  String? _error;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<String> _batches = [];
  String? _selectedBatch;
  Map<String, dynamic>? _batchAnalysis;
  bool _batchLoading = false;
  String? _batchError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await _api.getExamGroups();
      final students = await _api.getStudents();
      final batches = students
          .map((s) => s['batch_year']?.toString())
          .whereType<String>()
          .where((b) => b.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      setState(() {
        _groups = groups;
        _students = students;
        _batches = batches;
        _loading = false;
      });
      if (batches.isNotEmpty) {
        _selectBatch(batches.last);
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _selectBatch(String batch) async {
    setState(() {
      _selectedBatch = batch;
      _batchLoading = true;
      _batchError = null;
      _batchAnalysis = null;
    });
    try {
      final analysis = await _api.getBatchAnalysis(batch);
      setState(() {
        _batchAnalysis = analysis;
        _batchLoading = false;
      });
    } catch (e) {
      setState(() {
        _batchError = e.toString().replaceFirst('Exception: ', '');
        _batchLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    if (_searchQuery.isEmpty) return [];
    final q = _searchQuery.toLowerCase();
    return _students.where((s) {
      final name = (s['full_name']?.toString() ?? '').toLowerCase();
      final code = (s['student_code']?.toString() ?? '').toLowerCase();
      return name.contains(q) || code.contains(q);
    }).take(20).toList();
  }

  Future<void> _openStudent(Map<String, dynamic> student) async {
    final studentId = student['id']?.toString();
    if (studentId == null) return;
    if (_groups.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No exams imported yet')));
      return;
    }
    final examGroup = _groups.length == 1
        ? _groups.first['examGroup']?.toString()
        : await showModalBottomSheet<String>(
            context: context,
            builder: (ctx) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: _groups
                    .map((g) => ListTile(
                          title: Text(g['examGroup']?.toString() ?? ''),
                          onTap: () => Navigator.pop(ctx, g['examGroup']?.toString()),
                        ))
                    .toList(),
              ),
            ),
          );
    if (examGroup == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ExamReportScreen(examGroup: examGroup, studentId: studentId)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Cards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Customize Report Card',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExamTemplateEditorScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const ExamImportScreen()));
          _load();
        },
        icon: const Icon(Icons.upload_file),
        label: const Text('Import exam'),
      ),
      body: GlassBackdrop(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        _searchCard(),
                        if (_filteredStudents.isNotEmpty) _searchResultsCard(),
                        const SizedBox(height: 12),
                        if (_batches.isNotEmpty) _batchCard(),
                        const SizedBox(height: 12),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Text('Exam sittings', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        if (_groups.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: Text('No exams imported yet.\nTap "Import exam" to get started.', textAlign: TextAlign.center)),
                          )
                        else
                          ..._groups.map((g) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GlassContainer(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => ExamCohortScreen(examGroup: g['examGroup'])),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.assessment_outlined),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(g['examGroup']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text('${g['studentCount'] ?? 0} students', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, size: 18),
                                    ],
                                  ),
                                ),
                              )),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _searchCard() {
    return GlassContainer(
      child: TextField(
        controller: _searchController,
        decoration: const InputDecoration(
          hintText: 'Search a student by name or roll/student ID',
          prefixIcon: Icon(Icons.search),
          border: InputBorder.none,
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _searchResultsCard() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: _filteredStudents
              .map((s) => ListTile(
                    title: Text(s['full_name']?.toString() ?? ''),
                    subtitle: Text([s['student_code'], s['batch_year'], s['course_name']]
                        .where((v) => v != null && v.toString().isNotEmpty)
                        .join(' · ')),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => _openStudent(s),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _batchCard() {
    final risk = (_batchAnalysis?['riskCounts'] as Map?)?.cast<String, dynamic>();
    final total = risk == null ? 0 : (risk['low'] ?? 0) + (risk['medium'] ?? 0) + (risk['high'] ?? 0);
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Batch', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              DropdownButton<String>(
                value: _selectedBatch,
                underline: const SizedBox.shrink(),
                items: _batches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                onChanged: (v) {
                  if (v != null) _selectBatch(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_batchLoading)
            const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
          else if (_batchError != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_batchError!, style: const TextStyle(color: Colors.grey)))
          else if (_batchAnalysis != null) ...[
            Row(
              children: [
                Expanded(
                  child: _metricTile(
                    '${_batchAnalysis!['averageLatestPercentage']}%',
                    'Average (latest exam)',
                    Icons.trending_up,
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricTile(
                    '${_batchAnalysis!['analyzedCount']} / ${_batchAnalysis!['studentCount']}',
                    'Students with marks',
                    Icons.groups_outlined,
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (risk != null && total > 0) ...[
              const SizedBox(height: 12),
              _riskRow('Low risk', risk['low'] ?? 0, total, Colors.green),
              _riskRow('Medium risk', risk['medium'] ?? 0, total, Colors.orange),
              _riskRow('High risk', risk['high'] ?? 0, total, Colors.red),
            ],
            if (_batchAnalysis!['insight'] != null) ...[
              const SizedBox(height: 12),
              Text(_batchAnalysis!['insight'].toString(), style: const TextStyle(fontSize: 13)),
              if (_batchAnalysis!['insightIsFallback'] == true)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('(computed summary — AI insight unavailable)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _metricTile(String value, String label, IconData icon, Color color) {
    return GlassContainer(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.slate)),
        ],
      ),
    );
  }

  Widget _riskRow(String label, int value, int total, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? value / total : 0,
                minHeight: 8,
                backgroundColor: color.withValues(alpha: 0.08),
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 20, child: Text('$value', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
        ],
      ),
    );
  }
}
