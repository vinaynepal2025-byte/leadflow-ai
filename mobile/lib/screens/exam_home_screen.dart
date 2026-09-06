// lib/screens/exam_home_screen.dart
//
// Report Cards / Exam Intelligence — top-level landing screen.
//
// Deliberately its own independent section, not part of the Leads
// workflow: Leads is follow-up/sales-pipeline work on prospects; this is
// for already-enrolled students' exam results and report cards — a
// different job for a different screen, per the owner's explicit
// direction. Reached from the More menu like every other top-level
// section (see more_screen.dart's kMoreMenuDefaults), never from Lead
// Detail.

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/glass_widgets.dart';
import 'exam_import_screen.dart';
import 'exam_cohort_screen.dart';

class ExamHomeScreen extends StatefulWidget {
  const ExamHomeScreen({super.key});

  @override
  State<ExamHomeScreen> createState() => _ExamHomeScreenState();
}

class _ExamHomeScreenState extends State<ExamHomeScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _groups = [];
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
      final groups = await _api.getExamGroups();
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Cards')),
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
                  : _groups.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: const [
                            SizedBox(height: 40),
                            Center(child: Text('No exams imported yet.\nTap "Import exam" to get started.', textAlign: TextAlign.center)),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _groups.length,
                          itemBuilder: (context, i) {
                            final g = _groups[i];
                            return Padding(
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
                            );
                          },
                        ),
        ),
      ),
    );
  }
}
