import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/api_service.dart';
import 'lead_detail_screen.dart';

/// CRM Core gap fix: previously the only way to see leads was one flat
/// list, and the only way to change a lead's stage was opening its
/// detail screen. Every major CRM (Pipedrive, HubSpot, Zoho) treats a
/// visual, drag-to-move pipeline board as core UX, not an extra --
/// pipeline_builder_screen.dart only ever configured stage *names*, it
/// was never an actual working board. This is that board.
class PipelineBoardScreen extends StatefulWidget {
  const PipelineBoardScreen({super.key});

  @override
  State<PipelineBoardScreen> createState() => _PipelineBoardScreenState();
}

class _PipelineBoardScreenState extends State<PipelineBoardScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _stages = [];
  List<Lead> _leads = [];
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
      final results = await Future.wait([_api.getPipelineStages(), _api.getLeads()]);
      setState(() {
        _stages = results[0] as List<Map<String, dynamic>>;
        _leads = results[1] as List<Lead>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Optimistic move: the card jumps to the new column immediately (no
  /// spinner, no waiting on the network) and only reverts if the PATCH
  /// actually fails -- dragging a card that visibly lags behind your
  /// finger is exactly the kind of "cheap" feeling premium CRMs avoid.
  Future<void> _moveLead(Lead lead, String newStage) async {
    if (lead.stage == newStage) return;
    final oldStage = lead.stage;
    setState(() {
      final i = _leads.indexWhere((l) => l.id == lead.id);
      if (i != -1) _leads[i] = lead.copyWith(stage: newStage);
    });
    try {
      await _api.updateLead(lead.id, {'stage': newStage});
    } catch (e) {
      setState(() {
        final i = _leads.indexWhere((l) => l.id == lead.id);
        if (i != -1) _leads[i] = lead.copyWith(stage: oldStage);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not move lead: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pipeline Board'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load pipeline: $_error'))
              : _stages.isEmpty
                  ? const Center(child: Text('No pipeline stages configured yet.', style: TextStyle(color: Colors.grey)))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _stages.map((stage) => _column(stage)).toList(),
                      ),
                    ),
    );
  }

  Widget _column(Map<String, dynamic> stage) {
    final name = stage['name'] as String;
    final colorHex = (stage['color'] as String?) ?? '#607D8B';
    final color = Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000);
    final stageLeads = _leads.where((l) => l.stage == name).toList();

    return DragTarget<Lead>(
      onWillAcceptWithDetails: (details) => details.data.stage != name,
      onAcceptWithDetails: (details) => _moveLead(details.data, name),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          width: 260,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: isHovering ? color.withValues(alpha: 0.08) : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isHovering ? color : color.withValues(alpha: 0.25), width: isHovering ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                      child: Text('${stageLeads.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 560,
                child: stageLeads.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.only(top: 20),
                        child: Center(child: Text('Drop a lead here', style: TextStyle(color: Colors.grey, fontSize: 12))),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: stageLeads.length,
                        itemBuilder: (context, i) => _leadCard(stageLeads[i], color),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _leadCard(Lead lead, Color stageColor) {
    final card = Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 4, color: stageColor),
            Expanded(
              child: ListTile(
                dense: true,
                title: Text(lead.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: lead.source != null ? Text(lead.source!, style: const TextStyle(fontSize: 11)) : null,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: lead.id))),
              ),
            ),
          ],
        ),
      ),
    );

    return LongPressDraggable<Lead>(
      data: lead,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(width: 240, child: card),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: card,
    );
  }
}
