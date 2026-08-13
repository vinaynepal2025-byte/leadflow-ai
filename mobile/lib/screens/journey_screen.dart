import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'documents_screen.dart';

class JourneyScreen extends StatelessWidget {
  final String leadId;
  const JourneyScreen({super.key, required this.leadId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Visa, Travel & Student'),
          bottom: const TabBar(tabs: [Tab(text: 'Visa'), Tab(text: 'Travel'), Tab(text: 'Student')]),
        ),
        body: TabBarView(children: [_VisaTab(leadId: leadId), _TravelTab(leadId: leadId), _StudentTab(leadId: leadId)]),
      ),
    );
  }
}

class _VisaTab extends StatefulWidget {
  final String leadId;
  const _VisaTab({required this.leadId});
  @override
  State<_VisaTab> createState() => _VisaTabState();
}

class _VisaTabState extends State<_VisaTab> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;
  static const statuses = ['Not Started', 'Documents Pending', 'Submitted', 'Biometrics Done', 'Interview Scheduled', 'Approved', 'Rejected', 'Appealing'];

  @override
  void initState() {
    super.initState();
    _future = _api.getVisaApplications(widget.leadId);
  }

  void _refresh() => setState(() => _future = _api.getVisaApplications(widget.leadId));

  Future<void> _addDialog() async {
    final countryCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Visa Application'),
        content: TextField(controller: countryCtrl, decoration: const InputDecoration(labelText: 'Country')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (saved == true && countryCtrl.text.trim().isNotEmpty) {
      await _api.createVisaApplication(leadId: widget.leadId, country: countryCtrl.text.trim());
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final apps = snapshot.data ?? [];
          if (apps.isEmpty) return const Center(child: Text('No visa applications yet', style: TextStyle(color: Colors.grey)));
          return ListView.separated(
            itemCount: apps.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final v = apps[i];
              return ExpansionTile(
                title: Text(v['country']),
                subtitle: Text(v['embassy_location'] ?? ''),
                trailing: SizedBox(
                  width: 150,
                  child: DropdownButton<String>(
                    value: v['status'],
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 11)))).toList(),
                    onChanged: (val) async {
                      if (val != null) {
                        await _api.updateVisaApplication(v['id'], {'status': val});
                        _refresh();
                      }
                    },
                  ),
                ),
                children: [_VisaChecklist(visaId: v['id'], leadId: widget.leadId)],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addDialog, child: const Icon(Icons.add)),
    );
  }
}

// Per-country required-document checklist for a visa application,
// cross-referenced live against Documents — the concrete "no loopholes"
// piece: instead of the counselor remembering what's needed, the system
// shows exactly what's missing and lets them jump straight to uploading it.
class _VisaChecklist extends StatefulWidget {
  final String visaId;
  final String leadId;
  const _VisaChecklist({required this.visaId, required this.leadId});

  @override
  State<_VisaChecklist> createState() => _VisaChecklistState();
}

class _VisaChecklistState extends State<_VisaChecklist> {
  final _api = ApiService();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getVisaChecklist(widget.visaId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No checklist template set up for this country yet.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          );
        }
        final data = snapshot.data!;
        final checklist = (data['checklist'] as List? ?? []).cast<Map<String, dynamic>>();
        if (checklist.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No checklist template set up for this country yet.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          );
        }
        return Column(
          children: checklist.map((item) {
            final status = item['status'] as String;
            final ok = status == 'verified';
            final pending = status == 'pending';
            final rejected = status == 'rejected';
            final color = ok ? Colors.green : (rejected ? Colors.red : (pending ? Colors.orange : Colors.grey));
            final icon = ok
                ? Icons.check_circle
                : rejected
                    ? Icons.cancel
                    : pending
                        ? Icons.hourglass_bottom
                        : Icons.radio_button_unchecked;
            return ListTile(
              dense: true,
              leading: Icon(icon, color: color, size: 20),
              title: Text(item['doc_type'], style: const TextStyle(fontSize: 13)),
              trailing: (status == 'missing' || rejected)
                  ? TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DocumentsScreen(leadId: widget.leadId)),
                        );
                      },
                      child: const Text('Upload', style: TextStyle(fontSize: 12)),
                    )
                  : Text(status, style: TextStyle(color: color, fontSize: 11)),
            );
          }).toList(),
        );
      },
    );
  }
}

class _TravelTab extends StatefulWidget {
  final String leadId;
  const _TravelTab({required this.leadId});
  @override
  State<_TravelTab> createState() => _TravelTabState();
}

class _TravelTabState extends State<_TravelTab> {
  final _api = ApiService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getTravelPlans(widget.leadId);
  }

  void _refresh() => setState(() => _future = _api.getTravelPlans(widget.leadId));

  Future<void> _addDialog() async {
    final arrivalCtrl = TextEditingController();
    final airlineCtrl = TextEditingController();
    final flightCtrl = TextEditingController();
    final accCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Travel Plan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: arrivalCtrl, decoration: const InputDecoration(labelText: 'Arrival city')),
              TextField(controller: airlineCtrl, decoration: const InputDecoration(labelText: 'Airline')),
              TextField(controller: flightCtrl, decoration: const InputDecoration(labelText: 'Flight number')),
              TextField(controller: accCtrl, decoration: const InputDecoration(labelText: 'Accommodation')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (saved == true) {
      await _api.createTravelPlan(
        leadId: widget.leadId, arrivalCity: arrivalCtrl.text.trim().isEmpty ? null : arrivalCtrl.text.trim(),
        airline: airlineCtrl.text.trim().isEmpty ? null : airlineCtrl.text.trim(),
        flightNumber: flightCtrl.text.trim().isEmpty ? null : flightCtrl.text.trim(),
        accommodation: accCtrl.text.trim().isEmpty ? null : accCtrl.text.trim(),
      );
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final plans = snapshot.data ?? [];
          if (plans.isEmpty) return const Center(child: Text('No travel plan yet', style: TextStyle(color: Colors.grey)));
          return ListView.separated(
            itemCount: plans.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = plans[i];
              return ListTile(
                leading: const Icon(Icons.flight_takeoff),
                title: Text('${t['airline'] ?? 'Flight'} ${t['flight_number'] ?? ''} → ${t['arrival_city'] ?? ''}'),
                subtitle: Text('${t['accommodation'] ?? 'No accommodation set'} • ${t['status']}'),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addDialog, child: const Icon(Icons.add)),
    );
  }
}

class _StudentTab extends StatefulWidget {
  final String leadId;
  const _StudentTab({required this.leadId});
  @override
  State<_StudentTab> createState() => _StudentTabState();
}

class _StudentTabState extends State<_StudentTab> {
  final _api = ApiService();
  late Future<Map<String, dynamic>?> _future;
  late Future<List<Map<String, dynamic>>> _checkinsFuture;
  bool _alumniAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _api.getStudentForLead(widget.leadId);
  }

  Future<void> _enrollDialog() async {
    final instCtrl = TextEditingController();
    final courseCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enroll as Student'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: instCtrl, decoration: const InputDecoration(labelText: 'Institution')),
            TextField(controller: courseCtrl, decoration: const InputDecoration(labelText: 'Course')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enroll')),
        ],
      ),
    );
    if (saved == true && instCtrl.text.trim().isNotEmpty) {
      try {
        await _api.enrollStudent(leadId: widget.leadId, institutionName: instCtrl.text.trim(), courseName: courseCtrl.text.trim());
        setState(_load);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _checkinDialog(String studentId) async {
    String wellbeing = 'good';
    final issuesCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Check-in'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: wellbeing,
                items: const ['good', 'okay', 'struggling'].map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                onChanged: (v) => setDialogState(() => wellbeing = v ?? wellbeing),
                decoration: const InputDecoration(labelText: 'Wellbeing'),
              ),
              TextField(controller: issuesCtrl, decoration: const InputDecoration(labelText: 'Issues raised (if any)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved == true) {
      await _api.addStudentCheckin(studentId, wellbeing: wellbeing, issuesRaised: issuesCtrl.text.trim().isEmpty ? null : issuesCtrl.text.trim());
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final student = snapshot.data;
        if (student == null) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Not enrolled as a student yet', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _enrollDialog, icon: const Icon(Icons.school), label: const Text('Enroll as Student')),
                ],
              ),
            ),
          );
        }
        _checkinsFuture = _api.getStudentCheckins(student['id']);
        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(student['institution_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${student['course_name'] ?? ''} • Semester ${student['current_semester']}'),
                      Text('Status: ${student['status']}'),
                      const Divider(height: 20),
                      Row(
                        children: [
                          const Expanded(child: Text('Available for Alumni Network', style: TextStyle(fontSize: 13))),
                          Switch(
                            value: _alumniAvailable,
                            onChanged: (v) async {
                              await _api.setAlumniAvailability(student['id'], available: v);
                              setState(() => _alumniAvailable = v);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Check-ins', style: TextStyle(fontWeight: FontWeight.bold)),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _checkinsFuture,
                builder: (context, snap) {
                  final checkins = snap.data ?? [];
                  if (checkins.isEmpty) return const Padding(padding: EdgeInsets.only(top: 8), child: Text('No check-ins yet', style: TextStyle(color: Colors.grey)));
                  return Column(
                    children: checkins.map((c) => ListTile(
                          leading: Icon(Icons.circle, size: 10, color: c['wellbeing'] == 'struggling' ? Colors.red : c['wellbeing'] == 'okay' ? Colors.orange : Colors.green),
                          title: Text(c['wellbeing']),
                          subtitle: Text(c['issues_raised'] ?? c['checkin_date']),
                        )).toList(),
                  );
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _checkinDialog(student['id']),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Check-in'),
          ),
        );
      },
    );
  }
}
