// lib/screens/exam_report_screen.dart
//
// Exam Intelligence — one student's report: review the computed figures
// and AI narrative, correct a mark inline if needed (same logged-conflict
// path as a bulk re-import), generate the report card image, then send it
// on WhatsApp only after a human has confirmed the guardian number shown
// on screen. Nothing here should require re-typing anything already on
// file — student meta, guardian contact and every figure are pulled from
// what's already imported/recorded.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../widgets/glass_widgets.dart';

class ExamReportScreen extends StatefulWidget {
  final String examGroup;
  final String studentId;
  const ExamReportScreen({super.key, required this.examGroup, required this.studentId});

  @override
  State<ExamReportScreen> createState() => _ExamReportScreenState();
}

class _ExamReportScreenState extends State<ExamReportScreen> {
  final ApiService _api = ApiService();

  Map<String, dynamic>? _report; // from getExamReport
  Map<String, dynamic>? _generated; // from generateExamReportCard (guardian phone, narrative, etc.)
  Map<String, dynamic>? _analysis; // from getStudentAnalysis -- best-effort, missing is not an error
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _remarkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await _api.getExamReport(widget.examGroup, widget.studentId);
      setState(() {
        _report = report;
        _remarkController.text = report['teacherRemark']?.toString() ?? '';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
    // Best-effort: a student with only one exam recorded, or no attendance
    // data, still gets a full report -- the analysis card just doesn't show.
    try {
      final analysis = await _api.getStudentAnalysis(widget.studentId);
      if (mounted) setState(() => _analysis = analysis);
    } catch (_) {}
  }

  Future<void> _editMark(Map<String, dynamic> subject) async {
    final markId = subject['markId'];
    if (markId == null) {
      // No mark recorded yet for this subject — nothing to amend inline;
      // that has to come from an import.
      return;
    }
    final valueController = TextEditingController(text: subject['marksObtained']?.toString() ?? '');
    final reasonController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Correct ${subject['subject']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valueController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'New value (out of ${subject['maxMarks']})'),
            ),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason for the correction (required)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (result != true) return;
    final newValue = num.tryParse(valueController.text.trim());
    if (newValue == null || reasonController.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A value and a reason are both required')));
      return;
    }
    try {
      await _api.amendExamMark(markId, newValue: newValue, reason: reasonController.text.trim());
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mark corrected')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  /// Editing a subject's own maximum marks (not a student's obtained mark) --
  /// e.g. the sheet's header didn't state one, or the college corrected it
  /// after import. Once any mark already exists against this assessment,
  /// the backend requires confirmed:true + a reason (a stale percentage
  /// already shown to a parent under the old max is a real risk), so this
  /// always asks for a reason and only skips confirming twice if the first
  /// attempt comes back blocked.
  Future<void> _editMaxMarks(Map<String, dynamic> subject) async {
    final assessmentId = subject['assessmentId'];
    if (assessmentId == null) return;
    final valueController = TextEditingController(text: subject['maxMarks']?.toString() ?? '');
    final reasonController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit max marks — ${subject['subject']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valueController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Maximum marks for this subject'),
            ),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason (required if marks are already recorded)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (result != true) return;
    final newValue = num.tryParse(valueController.text.trim());
    if (newValue == null) return;
    try {
      final res = await _api.updateExamAssessment(assessmentId, {'max_marks': newValue}, reason: reasonController.text.trim().isEmpty ? null : reasonController.text.trim());
      if (res['blocked'] == true) {
        if (reasonController.text.trim().isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['reason']?.toString() ?? 'A reason is required')));
          }
          return;
        }
        await _api.updateExamAssessment(assessmentId, {'max_marks': newValue}, confirmed: true, reason: reasonController.text.trim());
      }
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max marks updated')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final generated = await _api.generateExamReportCard(
        widget.examGroup,
        widget.studentId,
        teacherRemark: _remarkController.text.trim(),
      );
      setState(() {
        _generated = generated;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  /// Free, semi-automatic send: opens WhatsApp with the report card link
  /// already filled in for the chosen guardian; a human still taps Send.
  /// The paid Meta Cloud API path (ApiService.sendExamReportCard) stays
  /// dormant until a paid WhatsApp Business tier is actually taken.
  Future<void> _sendToGuardian(String guardian) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await _api.getExamWhatsAppLink(widget.examGroup, widget.studentId, guardian: guardian);
      final url = link['whatsapp_link']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Could not build a WhatsApp link');
      }
      final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!launched) {
        throw Exception('Could not open WhatsApp');
      }
      // wa.me gives no delivery callback, so record the hand-off ourselves --
      // otherwise the send never appears in Communication Hub. Best-effort:
      // WhatsApp has already opened either way, so a logging failure here
      // shouldn't read as "the send failed" to the counselor.
      try {
        await _api.confirmExamWhatsAppSent(widget.examGroup, widget.studentId, guardian: guardian);
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opened WhatsApp for ${guardian == 'father' ? "father" : "mother"}${link['guardian_name'] != null ? ' (${link['guardian_name']})' : ''}')),
        );
      }
      setState(() => _busy = false);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  /// "Message" button: local plain-text send when WhatsApp isn't the
  /// choice -- opens the OS share sheet (SMS/any app), same proven pattern
  /// already used for flyer/document sharing elsewhere in this app. No
  /// specific recipient is pre-filled (the share sheet doesn't target one
  /// contact), unlike the WhatsApp buttons which go straight to a saved
  /// guardian number.
  Future<void> _sendPlainMessage() async {
    final meta = _report?['studentMeta'] as Map<String, dynamic>?;
    final summary = _report?['summary'] as Map<String, dynamic>?;
    final name = meta?['name']?.toString() ?? 'your child';
    final pct = summary?['overallPercentage'];
    final grade = summary?['overallGrade'];
    final examGroup = summary?['examGroup']?.toString() ?? widget.examGroup;
    final message = pct != null
        ? 'Hi, sharing $name\'s $examGroup result: $pct% (grade $grade).'
        : 'Hi, sharing $name\'s $examGroup report card with you.';
    try {
      await SharePlus.instance.share(ShareParams(text: message));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open share sheet: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _report?['summary'] as Map<String, dynamic>?;
    final meta = _report?['studentMeta'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(title: Text(meta?['name']?.toString() ?? 'Report')),
      body: GlassBackdrop(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && summary == null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (meta != null) _studentMetaCard(meta),
                      if (_analysis != null) ...[
                        const SizedBox(height: 12),
                        _analysisCard(),
                      ],
                      if (summary != null) ...[
                        const SizedBox(height: 12),
                        _summaryCard(summary),
                        const SizedBox(height: 12),
                        _subjectsCard(summary),
                        const SizedBox(height: 12),
                        _narrativeCard(),
                        const SizedBox(height: 12),
                        _remarkCard(),
                      ],
                      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                      const SizedBox(height: 16),
                      if (_generated == null)
                        GlassButton(onPressed: _busy ? null : _generate, icon: Icons.picture_as_pdf, child: const Text('Generate report card')),
                      if (_generated != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _generate,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Regenerate with this remark'),
                          ),
                        ),
                      if (_generated != null) _sendCard(),
                      if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator())),
                    ],
                  ),
      ),
    );
  }

  Widget _studentMetaCard(Map<String, dynamic> meta) {
    final line = [meta['studentCode'], meta['batch'], meta['course']].where((v) => v != null && v.toString().isNotEmpty).join(' · ');
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(meta['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          if (line.isNotEmpty) Text(line, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _summaryCard(Map<String, dynamic> summary) {
    return GlassContainer(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _stat('${summary['overallPercentage']}%', 'Overall'),
          _stat('${summary['overallGrade']}', 'Grade'),
          _stat('${summary['rank']}/${summary['cohortSize']}', 'Rank'),
          _stat('${summary['batchAverage']}/${summary['maxTotal']}', 'Batch avg'),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Column(children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]);

  Widget _subjectsCard(Map<String, dynamic> summary) {
    final subjects = (summary['subjects'] as List).cast<Map<String, dynamic>>();
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Subjects', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...subjects.map((s) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(s['subject']?.toString() ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s['marksObtained'] == null ? 'N/A' : '${s['marksObtained']} / ${s['maxMarks']}'),
                    if (s['markId'] != null)
                      IconButton(
                        icon: const Icon(Icons.edit, size: 16),
                        onPressed: () => _editMark(s),
                        tooltip: 'Correct this mark',
                      ),
                    IconButton(
                      icon: const Icon(Icons.rule, size: 16),
                      onPressed: () => _editMaxMarks(s),
                      tooltip: 'Edit max marks for this subject',
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _narrativeCard() {
    final narrative = _report?['narrative']?.toString();
    final isFallback = _report?['narrativeIsFallback'] == true;
    if (narrative == null) return const SizedBox.shrink();
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(narrative),
          if (isFallback)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('(computed summary — AI narrative unavailable)', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  /// A teacher's own free-text note for this specific student's card --
  /// distinct from the computed/AI narrative above. Printed on the card as
  /// its own labeled "Remark:" line (services/reportCardImage.js).
  Widget _remarkCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Teacher's remark (optional)", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _remarkController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'e.g. "Needs to focus more on Anatomy this term."',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sendCard() {
    final meta = _report?['studentMeta'] as Map<String, dynamic>?;
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Send result', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'F/M open WhatsApp with the report card link ready for that guardian — you confirm and tap Send. Message opens your phone\'s normal share options.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  meta?['name']?.toString() ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              _sendChip('F', 'Send to Father', _busy ? null : () => _sendToGuardian('father')),
              const SizedBox(width: 8),
              _sendChip('M', 'Send to Mother', _busy ? null : () => _sendToGuardian('mother')),
              const SizedBox(width: 8),
              _sendChip('✉', 'Message (SMS / other app)', _busy ? null : _sendPlainMessage),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sendChip(String label, String tooltip, VoidCallback? onPressed) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _analysisCard() {
    final risk = _analysis!['overallRisk']?.toString() ?? 'unknown';
    final riskColor = risk == 'high' ? Colors.red : (risk == 'medium' ? Colors.orange : Colors.green);
    final evidence = (_analysis!['evidence'] as Map?)?.cast<String, dynamic>();
    final trend = evidence?['trend'];
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Academic analysis', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: riskColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  '${risk[0].toUpperCase()}${risk.substring(1)} risk',
                  style: TextStyle(color: riskColor, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          if (trend != null) ...[
            const SizedBox(height: 6),
            Text(
              '${trend >= 0 ? '▲' : '▼'} ${trend.abs()} points vs previous exam',
              style: TextStyle(fontSize: 12, color: trend >= 0 ? Colors.green[700] : Colors.red[700]),
            ),
          ],
          const SizedBox(height: 8),
          Text(_analysis!['insight']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
          if (_analysis!['recommendation'] != null) ...[
            const SizedBox(height: 6),
            Text('→ ${_analysis!['recommendation']}', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
          ],
          if (_analysis!['insightIsFallback'] == true)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('(computed summary — AI insight unavailable)', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
        ],
      ),
    );
  }
}
