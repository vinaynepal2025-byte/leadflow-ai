// lib/screens/exam_cohort_screen.dart
//
// Exam Intelligence — every student ranked for one exam sitting. What the
// counselor actually sees here is already scoped server-side: owner/admin
// see the whole tenant, everyone else only their own assigned caseload
// (see backend/routes/exams.js's canAccessStudent / the cohort route).

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/glass_widgets.dart';
import 'exam_report_screen.dart';

class ExamCohortScreen extends StatefulWidget {
  final String examGroup;
  const ExamCohortScreen({super.key, required this.examGroup});

  @override
  State<ExamCohortScreen> createState() => _ExamCohortScreenState();
}

class _ExamCohortScreenState extends State<ExamCohortScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _cohort = [];
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
      final cohort = await _api.getExamCohort(widget.examGroup);
      setState(() {
        _cohort = cohort;
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
      appBar: AppBar(title: Text(widget.examGroup, overflow: TextOverflow.ellipsis)),
      body: GlassBackdrop(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                  : _cohort.isEmpty
                      ? const Center(child: Text('No marks recorded for this exam yet'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _cohort.length,
                          itemBuilder: (context, i) {
                            final row = _cohort[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GlassContainer(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ExamReportScreen(examGroup: widget.examGroup, studentId: row['studentId']),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(radius: 16, child: Text('${row['rank']}', style: const TextStyle(fontSize: 12))),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(row['name']?.toString() ?? '', overflow: TextOverflow.ellipsis)),
                                    Text('${row['total']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 8),
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
