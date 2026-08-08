import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lead.dart';
import '../models/communication.dart';
import '../models/reminder.dart';

/// Central place the app talks to the backend from.
/// Change [baseUrl] to your deployed backend's real address when you go live
/// (right now it points at a local dev server for testing).
class ApiService {
  // Not a hardcoded constant — once the app is installed on a real phone,
  // "localhost" means the phone itself, not a development machine. This
  // is loaded from SharedPreferences at startup and changeable from
  // Settings, so pointing the installed app at your real deployed
  // backend never requires rebuilding the app.
  static String baseUrl = 'https://leadflow-ai-backend-e50r.onrender.com';
  static const _baseUrlKey = 'api_base_url';

  static Future<void> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_baseUrlKey) ?? 'https://leadflow-ai-backend-e50r.onrender.com';
  }

  static Future<void> setBaseUrl(String url) async {
    // Strip a trailing slash so "https://api.example.com/" and
    // "https://api.example.com" behave identically everywhere.
    baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, baseUrl);
  }

  /// In production, tenantId comes from the logged-in user's session
  /// (Identity module, not yet built). Fixed for now so every screen works
  /// end-to-end against the backend that already exists.
  static const String tenantId = 'demo-consultancy';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-tenant-id': tenantId,
      };

  // ---------- Leads ----------

  Future<List<Lead>> getLeads({String? stage, bool? hasParent}) async {
    final uri = Uri.parse('$baseUrl/leads').replace(
      queryParameters: {
        if (stage != null) 'stage': stage,
        if (hasParent == true) 'has_parent': 'true',
      },
    );
    final res = await http.get(uri, headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.map((e) => Lead.fromJson(e)).toList();
  }

  Future<void> deleteLead(String id) async {
    final res = await http.delete(Uri.parse('$baseUrl/leads/$id'), headers: _headers);
    if (res.statusCode != 204) throw Exception('Could not delete lead');
  }

  Future<Lead> getLead(String id) async {
    final res = await http.get(Uri.parse('$baseUrl/leads/$id'), headers: _headers);
    _checkOk(res);
    return Lead.fromJson(jsonDecode(res.body));
  }

  Future<Lead> createLead({
    required String fullName,
    String? phone,
    String? email,
    String? source,
    String? assignedTo,
    String? notes,
    String? parentName,
    String? parentPhone,
    String? parentRelation,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/leads'),
      headers: _headers,
      body: jsonEncode({
        'full_name': fullName,
        'phone': phone,
        'email': email,
        'source': source,
        'assigned_to': assignedTo,
        'notes': notes,
        'parent_name': parentName,
        'parent_phone': parentPhone,
        'parent_relation': parentRelation,
      }),
    );
    _checkOk(res, expected: 201);
    return Lead.fromJson(jsonDecode(res.body));
  }

  Future<Lead> updateLeadStage(String id, String newStage) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/leads/$id'),
      headers: _headers,
      body: jsonEncode({'stage': newStage}),
    );
    _checkOk(res);
    return Lead.fromJson(jsonDecode(res.body));
  }

  // ---------- Communications ----------

  Future<List<Communication>> getCommunications(String leadId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/communications').replace(queryParameters: {'lead_id': leadId}),
      headers: _headers,
    );
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.map((e) => Communication.fromJson(e)).toList();
  }

  Future<void> logCommunication({
    required String leadId,
    required String channel,
    required String direction,
    String? body,
    String? createdBy,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/communications'),
      headers: _headers,
      body: jsonEncode({
        'lead_id': leadId,
        'channel': channel,
        'direction': direction,
        'body': body,
        'created_by': createdBy,
      }),
    );
    _checkOk(res, expected: 201);
  }

  // ---------- WhatsApp (free wa.me method) ----------

  Future<String> getWhatsAppChatLink(String leadId, String message) async {
    final res = await http.get(
      Uri.parse('$baseUrl/whatsapp/chat-link/$leadId')
          .replace(queryParameters: {'message': message}),
      headers: _headers,
    );
    _checkOk(res);
    return jsonDecode(res.body)['chat_link'] as String;
  }

  Future<void> confirmWhatsAppSent(String leadId, String message, String createdBy) async {
    final res = await http.post(
      Uri.parse('$baseUrl/whatsapp/chat-link/$leadId/confirm-sent'),
      headers: _headers,
      body: jsonEncode({'message': message, 'created_by': createdBy}),
    );
    _checkOk(res, expected: 201);
  }

  // ---------- AI Analysis ----------

  Future<AiInsight> analyzeLead(String leadId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/ai/analyze-lead/$leadId'),
      headers: _headers,
    );
    if (res.statusCode == 502) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'AI not configured yet');
    }
    _checkOk(res);
    return AiInsight.fromJson(jsonDecode(res.body));
  }

  // ---------- AI Design Engine ----------
  // Portable: this method + the backend's POST /ai/generate-theme route
  // have no LeadFlow-specific coupling -- copy both into any other
  // project that shares this app's theme/ folder shape.

  Future<Map<String, dynamic>> generateAiTheme(String prompt, {List<String>? brandColors}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/ai/generate-theme'),
      headers: _headers,
      body: jsonEncode({
        'prompt': prompt,
        if (brandColors != null) 'brandColors': brandColors,
      }),
    );
    if (res.statusCode == 502 || res.statusCode == 400) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'AI theme generation failed');
    }
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------- Reminders ----------

  Future<List<ReminderItem>> getReminders({String? status, String? leadId}) async {
    final params = <String, String>{};
    if (status != null) params['status'] = status;
    if (leadId != null) params['lead_id'] = leadId;
    final res = await http.get(
      Uri.parse('$baseUrl/reminders').replace(queryParameters: params.isEmpty ? null : params),
      headers: _headers,
    );
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.map((e) => ReminderItem.fromJson(e)).toList();
  }

  Future<void> createReminder({
    required String leadId,
    required String title,
    required String dueAt,
    String? assignedTo,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/reminders'),
      headers: _headers,
      body: jsonEncode({
        'lead_id': leadId,
        'title': title,
        'due_at': dueAt,
        'assigned_to': assignedTo,
      }),
    );
    _checkOk(res, expected: 201);
  }

  Future<void> markReminderDone(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/reminders/$id'),
      headers: _headers,
      body: jsonEncode({'status': 'done'}),
    );
    _checkOk(res);
  }

  // ---------- Analytics ----------

  Future<Map<String, dynamic>> getAnalyticsSummary() async {
    final res = await http.get(Uri.parse('$baseUrl/analytics/summary'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------- Documents ----------

  Future<List<Map<String, dynamic>>> getDocuments(String leadId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/documents').replace(queryParameters: {'lead_id': leadId}),
      headers: _headers,
    );
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> uploadDocument({
    required String leadId,
    required String docType,
    required String filePath,
    required String fileName,
    String? uploadedBy,
  }) async {
    final uri = Uri.parse('$baseUrl/documents');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'x-tenant-id': tenantId})
      ..fields['lead_id'] = leadId
      ..fields['doc_type'] = docType
      ..fields['uploaded_by'] = uploadedBy ?? ''
      ..files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));

    final streamed = await request.send();
    if (streamed.statusCode != 201) {
      final body = await streamed.stream.bytesToString();
      throw Exception('Upload failed: $body');
    }
  }

  String getDocumentDownloadUrl(String docId) => '$baseUrl/documents/$docId/download';

  Future<void> setDocumentStatus(String docId, String status) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/documents/$docId'),
      headers: _headers,
      body: jsonEncode({'status': status}),
    );
    _checkOk(res);
  }

  // ---------- Tasks ----------

  Future<List<Map<String, dynamic>>> getTasks({String? status}) async {
    final res = await http.get(
      Uri.parse('$baseUrl/tasks').replace(queryParameters: status != null ? {'status': status} : null),
      headers: _headers,
    );
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> createTask({required String title, String? dueAt, String? assignedTo, String priority = 'normal'}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/tasks'),
      headers: _headers,
      body: jsonEncode({'title': title, 'due_at': dueAt, 'assigned_to': assignedTo, 'priority': priority}),
    );
    _checkOk(res, expected: 201);
  }

  Future<void> markTaskDone(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/tasks/$id'),
      headers: _headers,
      body: jsonEncode({'status': 'done'}),
    );
    _checkOk(res);
  }

  // ---------- Notifications ----------

  Future<List<Map<String, dynamic>>> getNotifications() async {
    final res = await http.get(Uri.parse('$baseUrl/notifications'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<int> getUnreadCount() async {
    final res = await http.get(Uri.parse('$baseUrl/notifications/unread-count'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body)['count'] as int;
  }

  Future<void> markAllNotificationsRead() async {
    final res = await http.post(Uri.parse('$baseUrl/notifications/read-all'), headers: _headers);
    _checkOk(res);
  }

  // ---------- Admissions ----------

  Future<List<Map<String, dynamic>>> getAdmissions(String leadId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/admissions').replace(queryParameters: {'lead_id': leadId}),
      headers: _headers,
    );
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> addAdmission({
    required String leadId,
    required String institutionName,
    String? courseName,
    String? intake,
    double? tuitionFee,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/admissions'),
      headers: _headers,
      body: jsonEncode({
        'lead_id': leadId,
        'institution_name': institutionName,
        'course_name': courseName,
        'intake': intake,
        'tuition_fee': tuitionFee,
      }),
    );
    _checkOk(res, expected: 201);
  }

  Future<void> updateAdmissionStatus(String id, String status) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/admissions/$id'),
      headers: _headers,
      body: jsonEncode({'application_status': status}),
    );
    _checkOk(res);
  }

  // ---------- Fees ----------

  Future<List<Map<String, dynamic>>> getFees(String leadId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/fees').replace(queryParameters: {'lead_id': leadId}),
      headers: _headers,
    );
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> addFee({required String leadId, required String feeType, required double amount, String? dueDate}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/fees'),
      headers: _headers,
      body: jsonEncode({'lead_id': leadId, 'fee_type': feeType, 'amount': amount, 'due_date': dueDate}),
    );
    _checkOk(res, expected: 201);
  }

  Future<void> markFeePaid(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/fees/$id'),
      headers: _headers,
      body: jsonEncode({'status': 'paid'}),
    );
    _checkOk(res);
  }

  // ---------- Campaigns ----------

  Future<List<Map<String, dynamic>>> getCampaigns() async {
    final res = await http.get(Uri.parse('$baseUrl/campaigns'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> createCampaign({required String name, required String messageTemplate, String? source, String? stage}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/campaigns'),
      headers: _headers,
      body: jsonEncode({'name': name, 'message_template': messageTemplate, 'source': source, 'stage': stage}),
    );
    _checkOk(res, expected: 201);
  }

  Future<Map<String, dynamic>> getCampaignLinks(String campaignId) async {
    final res = await http.get(Uri.parse('$baseUrl/campaigns/$campaignId/links'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> confirmCampaignTargetSent(String targetId) async {
    final res = await http.post(Uri.parse('$baseUrl/campaigns/targets/$targetId/confirm-sent'), headers: _headers);
    _checkOk(res);
  }

  // ---------- Settings ----------

  Future<Map<String, dynamic>> getSettings() async {
    final res = await http.get(Uri.parse('$baseUrl/settings'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> updateSettings(Map<String, dynamic> fields) async {
    final res = await http.patch(Uri.parse('$baseUrl/settings'), headers: _headers, body: jsonEncode(fields));
    _checkOk(res);
  }

  // ---------- Performance ----------

  Future<List<Map<String, dynamic>>> getPerformance() async {
    final res = await http.get(Uri.parse('$baseUrl/performance'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ---------- Audit ----------

  Future<List<Map<String, dynamic>>> getAuditTimeline({String? leadId}) async {
    final res = await http.get(
      Uri.parse('$baseUrl/audit').replace(queryParameters: leadId != null ? {'lead_id': leadId} : null),
      headers: _headers,
    );
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ---------- Knowledge Base ----------

  Future<List<Map<String, dynamic>>> getKnowledgeArticles({String? q}) async {
    final res = await http.get(
      Uri.parse('$baseUrl/knowledge').replace(queryParameters: q != null && q.isNotEmpty ? {'q': q} : null),
      headers: _headers,
    );
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> createKnowledgeArticle({required String title, required String content, String? category}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/knowledge'),
      headers: _headers,
      body: jsonEncode({'title': title, 'content': content, 'category': category}),
    );
    _checkOk(res, expected: 201);
  }

  // ---------- Automations ----------

  Future<List<Map<String, dynamic>>> getAutomations() async {
    final res = await http.get(Uri.parse('$baseUrl/automations'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> createAutomation({
    required String name,
    required String triggerEvent,
    required String actionType,
    required Map<String, dynamic> actionConfig,
    String? conditionField,
    String? conditionValue,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/automations'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'trigger_event': triggerEvent,
        'action_type': actionType,
        'action_config': actionConfig,
        'condition_field': conditionField,
        'condition_value': conditionValue,
      }),
    );
    _checkOk(res, expected: 201);
  }

  Future<void> setAutomationEnabled(String id, bool enabled) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/automations/$id'),
      headers: _headers,
      body: jsonEncode({'enabled': enabled}),
    );
    _checkOk(res);
  }

  // ---------- Contact Import ----------

  Future<Map<String, dynamic>> importLeadsCsv(String filePath, String fileName) async {
    final uri = Uri.parse('$baseUrl/leads/import');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'x-tenant-id': tenantId})
      ..files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 201) {
      throw Exception(jsonDecode(body)['error'] ?? 'Import failed');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  // ---------- Email ----------

  Future<void> sendEmail({required String leadId, required String subject, required String message, String? createdBy}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/email/send'),
      headers: _headers,
      body: jsonEncode({'lead_id': leadId, 'subject': subject, 'message': message, 'created_by': createdBy}),
    );
    if (res.statusCode == 502) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Email not configured');
    }
    _checkOk(res, expected: 201);
  }

  // ---------- Call Manager ----------

  Future<List<Map<String, dynamic>>> getCalls(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/calls').replace(queryParameters: {'lead_id': leadId}), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> logCall({required String leadId, required String outcome, int? durationSeconds, String? notes, String? calledBy}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/calls'),
      headers: _headers,
      body: jsonEncode({
        'lead_id': leadId, 'outcome': outcome, 'duration_seconds': durationSeconds,
        'notes': notes, 'called_by': calledBy,
      }),
    );
    _checkOk(res, expected: 201);
  }

  // ---------- Voice Notes ----------

  String getVoiceNoteDownloadUrl(String noteId) => '$baseUrl/voice-notes/$noteId/download';

  Future<List<int>> downloadVoiceNoteBytes(String noteId) async {
    final res = await http.get(Uri.parse(getVoiceNoteDownloadUrl(noteId)), headers: _headers);
    if (res.statusCode != 200) throw Exception('Could not download voice note');
    return res.bodyBytes;
  }

  Future<List<Map<String, dynamic>>> getVoiceNotes(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/voice-notes').replace(queryParameters: {'lead_id': leadId}), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> uploadVoiceNote({required String leadId, required String filePath, required String fileName, String? recordedBy}) async {
    final uri = Uri.parse('$baseUrl/voice-notes');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'x-tenant-id': tenantId})
      ..fields['lead_id'] = leadId
      ..fields['recorded_by'] = recordedBy ?? ''
      ..files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamed = await request.send();
    if (streamed.statusCode != 201) {
      final body = await streamed.stream.bytesToString();
      throw Exception('Upload failed: $body');
    }
  }

  Future<void> attachTranscript(String voiceNoteId, String transcript) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/voice-notes/$voiceNoteId'),
      headers: _headers,
      body: jsonEncode({'transcript': transcript}),
    );
    _checkOk(res);
  }

  Future<String> summarizeVoiceNote(String voiceNoteId) async {
    final res = await http.post(Uri.parse('$baseUrl/voice-notes/$voiceNoteId/summarize'), headers: _headers);
    if (res.statusCode == 502 || res.statusCode == 400) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Summary failed');
    }
    _checkOk(res);
    return jsonDecode(res.body)['ai_summary'] as String;
  }

  // ---------- Calendar ----------

  Future<List<Map<String, dynamic>>> getCalendar({String? from, String? to}) async {
    final params = <String, String>{};
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;
    final res = await http.get(Uri.parse('$baseUrl/calendar').replace(queryParameters: params.isEmpty ? null : params), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<String> uploadLogo(String filePath, String fileName) async {
    final uri = Uri.parse('$baseUrl/settings/logo');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'x-tenant-id': tenantId})
      ..files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 201) throw Exception('Logo upload failed: $body');
    return jsonDecode(body)['logo_url'] as String;
  }

  // ---------- Colleges (College CRM) ----------

  Future<List<Map<String, dynamic>>> getColleges() async {
    final res = await http.get(Uri.parse('$baseUrl/colleges'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> createCollege({required String name, String? country, String? contactPerson, double? commissionPercent}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/colleges'),
      headers: _headers,
      body: jsonEncode({'name': name, 'country': country, 'contact_person': contactPerson, 'commission_percent': commissionPercent}),
    );
    _checkOk(res, expected: 201);
  }

  Future<List<Map<String, dynamic>>> getTeam() async {
    final res = await http.get(Uri.parse('$baseUrl/auth/team'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> checkDuplicateLead({String? fullName, String? phone}) async {
    final params = <String, String>{};
    if (fullName != null && fullName.isNotEmpty) params['full_name'] = fullName;
    if (phone != null && phone.isNotEmpty) params['phone'] = phone;
    if (params.isEmpty) return [];
    final res = await http.get(Uri.parse('$baseUrl/leads/check-duplicate').replace(queryParameters: params), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> importLeadsExcel(String filePath, String fileName) async {
    final uri = Uri.parse('$baseUrl/leads/import-excel');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'x-tenant-id': tenantId})
      ..files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 201) {
      throw Exception(jsonDecode(body)['error'] ?? 'Import failed');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  // ---------- Custom Fields Builder ----------

  Future<List<Map<String, dynamic>>> getCustomFieldDefinitions() async {
    final res = await http.get(Uri.parse('$baseUrl/custom-fields'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> createCustomFieldDefinition({
    required String fieldKey,
    required String label,
    required String fieldType,
    List<String>? options,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/custom-fields'),
      headers: _headers,
      body: jsonEncode({'field_key': fieldKey, 'label': label, 'field_type': fieldType, 'options': options}),
    );
    if (res.statusCode == 409 || res.statusCode == 400) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Could not create field');
    }
    _checkOk(res, expected: 201);
  }

  Future<void> deleteCustomFieldDefinition(String id) async {
    final res = await http.delete(Uri.parse('$baseUrl/custom-fields/$id'), headers: _headers);
    if (res.statusCode != 204) throw Exception('Could not delete field');
  }

  Future<void> setLeadCustomField(String leadId, String fieldKey, dynamic value) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/leads/$leadId'),
      headers: _headers,
      body: jsonEncode({'custom_fields': {fieldKey: value}}),
    );
    _checkOk(res);
  }

  // ---------- Pipeline Builder ----------

  Future<List<Map<String, dynamic>>> getPipelineStages() async {
    final res = await http.get(Uri.parse('$baseUrl/pipeline-stages'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> createPipelineStage({required String name, String? color}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/pipeline-stages'),
      headers: _headers,
      body: jsonEncode({'name': name, 'color': color}),
    );
    _checkOk(res, expected: 201);
  }

  Future<void> deletePipelineStage(String id) async {
    final res = await http.delete(Uri.parse('$baseUrl/pipeline-stages/$id'), headers: _headers);
    if (res.statusCode != 204) throw Exception('Could not delete stage');
  }

  // ---------- Lead Scoring ----------

  Future<Map<String, dynamic>> getTodayQueue() async {
    final res = await http.get(Uri.parse('$baseUrl/scoring/today'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getLeadScore(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/scoring/lead/$leadId'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getRankedLeads({String? temperature}) async {
    final res = await http.get(
      Uri.parse('$baseUrl/scoring/ranked').replace(queryParameters: temperature != null ? {'temperature': temperature} : null),
      headers: _headers,
    );
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ---------- Meetings & Campus Tours ----------

  Future<List<Map<String, dynamic>>> getMeetings({String? leadId, bool upcoming = false}) async {
    final params = <String, String>{};
    if (leadId != null) params['lead_id'] = leadId;
    if (upcoming) params['upcoming'] = 'true';
    final res = await http.get(Uri.parse('$baseUrl/meetings').replace(queryParameters: params.isEmpty ? null : params), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createMeeting({
    required String leadId,
    required String meetingType,
    required String title,
    required String scheduledAt,
    String mode = 'online',
    String? meetingLink,
    String? location,
    String? campusName,
    String? hostName,
    String? requestedBy,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/meetings'),
      headers: _headers,
      body: jsonEncode({
        'lead_id': leadId, 'meeting_type': meetingType, 'title': title, 'scheduled_at': scheduledAt,
        'mode': mode, 'meeting_link': meetingLink, 'location': location,
        'campus_name': campusName, 'host_name': hostName, 'requested_by': requestedBy,
      }),
    );
    _checkOk(res, expected: 201);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> updateMeeting(String id, Map<String, dynamic> fields) async {
    final res = await http.patch(Uri.parse('$baseUrl/meetings/$id'), headers: _headers, body: jsonEncode(fields));
    _checkOk(res);
  }

  Future<Map<String, dynamic>> updateMeetingVisitDetails(String id, Map<String, dynamic> fields) async {
    final res = await http.patch(Uri.parse('$baseUrl/meetings/$id/visit-details'), headers: _headers, body: jsonEncode(fields));
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------- Colleges: peer-review config ----------

  Future<void> updateCollege(String id, Map<String, dynamic> fields) async {
    final res = await http.patch(Uri.parse('$baseUrl/colleges/$id'), headers: _headers, body: jsonEncode(fields));
    _checkOk(res);
  }

  // ---------- Paid Peer-Review Marketplace ----------
  // Portable pattern: payment is a device UPI-intent link straight to the
  // provider's own UPI ID -- no gateway approval needed to go live.

  Future<List<Map<String, dynamic>>> getReviewProviders({String? collegeId, bool activeOnly = true}) async {
    final params = <String, String>{};
    if (collegeId != null) params['college_id'] = collegeId;
    if (!activeOnly) params['active_only'] = 'false';
    final res = await http.get(Uri.parse('$baseUrl/review-providers').replace(queryParameters: params.isEmpty ? null : params), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> registerReviewProvider({
    required String collegeId,
    required String fullName,
    String? role,
    String? phone,
    required String upiId,
    double? pricePerReview,
    String? bio,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/review-providers'),
      headers: _headers,
      body: jsonEncode({
        'college_id': collegeId, 'full_name': fullName, 'role': role, 'phone': phone,
        'upi_id': upiId, 'price_per_review': pricePerReview, 'bio': bio,
      }),
    );
    if (res.statusCode == 400) throw Exception(jsonDecode(res.body)['error'] ?? 'Registration failed');
    _checkOk(res, expected: 201);
  }

  Future<void> updateReviewProvider(String id, Map<String, dynamic> fields) async {
    final res = await http.patch(Uri.parse('$baseUrl/review-providers/$id'), headers: _headers, body: jsonEncode(fields));
    _checkOk(res);
  }

  Future<Map<String, dynamic>> bookPeerReview({required String leadId, required String collegeId, required String providerId, int? durationMinutes}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/peer-reviews'),
      headers: _headers,
      body: jsonEncode({
        'lead_id': leadId,
        'college_id': collegeId,
        'provider_id': providerId,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
      }),
    );
    if (res.statusCode == 400 || res.statusCode == 404) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Booking failed');
    }
    _checkOk(res, expected: 201);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> confirmPeerReviewPayment(String bookingId, {String? paymentNote}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/peer-reviews/$bookingId/confirm-payment'),
      headers: _headers,
      body: jsonEncode({'payment_note': paymentNote}),
    );
    _checkOk(res);
  }

  Future<void> completePeerReview(String bookingId, {int? rating, String? reviewNotes}) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/peer-reviews/$bookingId/complete'),
      headers: _headers,
      body: jsonEncode({'rating': rating, 'review_notes': reviewNotes}),
    );
    _checkOk(res);
  }

  Future<List<Map<String, dynamic>>> getPeerReviews({String? leadId, String? providerId}) async {
    final params = <String, String>{};
    if (leadId != null) params['lead_id'] = leadId;
    if (providerId != null) params['provider_id'] = providerId;
    final res = await http.get(Uri.parse('$baseUrl/peer-reviews').replace(queryParameters: params.isEmpty ? null : params), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ---------- Lead Scoring ----------


  Future<Map<String, dynamic>> getScoringToday() async {
    final res = await http.get(Uri.parse('$baseUrl/scoring/today'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------- Social Media Links ----------

  // ---------- Social Media Links ----------

  Future<List<Map<String, dynamic>>> getTrackedLinks() async {
    final res = await http.get(Uri.parse('$baseUrl/social/links'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createTrackedLink({
    required String title,
    required String platform,
    String? captureFormId,
    String? destination,
    String? campaign,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/social/links'),
      headers: _headers,
      body: jsonEncode({'title': title, 'platform': platform, 'capture_form_id': captureFormId, 'destination': destination, 'campaign': campaign}),
    );
    _checkOk(res, expected: 201);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSocialPerformance() async {
    final res = await http.get(Uri.parse('$baseUrl/social/performance'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getCaptureForms() async {
    final res = await http.get(Uri.parse('$baseUrl/capture/forms'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> createCaptureForm({required String name, required String channel, String? assignTo, String? autoReplyMessage}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/capture/forms'),
      headers: _headers,
      body: jsonEncode({'name': name, 'channel': channel, 'assign_to': assignTo, 'auto_reply_message': autoReplyMessage}),
    );
    _checkOk(res, expected: 201);
  }

  // ---------- Scoring Config ----------

  Future<Map<String, dynamic>> getScoringConfig() async {
    final res = await http.get(Uri.parse('$baseUrl/scoring/config'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> previewScoringConfig(Map<String, num> weightChanges) async {
    final res = await http.post(
      Uri.parse('$baseUrl/scoring/config/preview'),
      headers: _headers,
      body: jsonEncode({'weights': weightChanges}),
    );
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> saveScoringConfig(Map<String, num> weightChanges) async {
    final res = await http.put(
      Uri.parse('$baseUrl/scoring/config'),
      headers: _headers,
      body: jsonEncode({'weights': weightChanges}),
    );
    if (res.statusCode == 400) throw Exception(jsonDecode(res.body)['error']);
    _checkOk(res);
  }

  Future<void> resetScoringConfig() async {
    final res = await http.post(Uri.parse('$baseUrl/scoring/config/reset'), headers: _headers);
    _checkOk(res);
  }

  // ---------- Visa & Travel ----------

  Future<List<Map<String, dynamic>>> getVisaApplications(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/journey/visa').replace(queryParameters: {'lead_id': leadId}), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> createVisaApplication({required String leadId, required String country, String? embassyLocation}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/journey/visa'),
      headers: _headers,
      body: jsonEncode({'lead_id': leadId, 'country': country, 'embassy_location': embassyLocation}),
    );
    _checkOk(res, expected: 201);
  }

  Future<void> updateVisaApplication(String id, Map<String, dynamic> fields) async {
    final res = await http.patch(Uri.parse('$baseUrl/journey/visa/$id'), headers: _headers, body: jsonEncode(fields));
    _checkOk(res);
  }

  Future<List<Map<String, dynamic>>> getTravelPlans(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/journey/travel').replace(queryParameters: {'lead_id': leadId}), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> createTravelPlan({required String leadId, String? departureDate, String? arrivalCity, String? airline, String? flightNumber, String? accommodation}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/journey/travel'),
      headers: _headers,
      body: jsonEncode({
        'lead_id': leadId, 'departure_date': departureDate, 'arrival_city': arrivalCity,
        'airline': airline, 'flight_number': flightNumber, 'accommodation': accommodation,
      }),
    );
    _checkOk(res, expected: 201);
  }

  // ---------- Student Lifecycle ----------

  Future<Map<String, dynamic>?> getStudentForLead(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/students'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    final match = data.cast<Map<String, dynamic>>().where((s) => s['lead_id'] == leadId);
    return match.isEmpty ? null : match.first;
  }

  Future<void> enrollStudent({required String leadId, required String institutionName, String? courseName, String? studentCode, String? batchYear}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/students'),
      headers: _headers,
      body: jsonEncode({'lead_id': leadId, 'institution_name': institutionName, 'course_name': courseName, 'student_code': studentCode, 'batch_year': batchYear}),
    );
    if (res.statusCode == 409) throw Exception(jsonDecode(res.body)['error']);
    _checkOk(res, expected: 201);
  }

  Future<void> updateStudent(String id, Map<String, dynamic> fields) async {
    final res = await http.patch(Uri.parse('$baseUrl/students/$id'), headers: _headers, body: jsonEncode(fields));
    _checkOk(res);
  }

  Future<List<Map<String, dynamic>>> getStudentCheckins(String studentId) async {
    final res = await http.get(Uri.parse('$baseUrl/students/$studentId/checkins'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> addStudentCheckin(String studentId, {required String wellbeing, String? issuesRaised, String? actionTaken}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/students/$studentId/checkins'),
      headers: _headers,
      body: jsonEncode({'wellbeing': wellbeing, 'issues_raised': issuesRaised, 'action_taken': actionTaken, 'conducted_by': 'Counselor'}),
    );
    _checkOk(res, expected: 201);
  }

  // ---------- Unified Inbox ----------

  Future<List<Map<String, dynamic>>> getInbox({String? channel}) async {
    final res = await http.get(Uri.parse('$baseUrl/inbox').replace(queryParameters: channel != null ? {'channel': channel} : null), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getUnrepliedInbox() async {
    final res = await http.get(Uri.parse('$baseUrl/inbox/unreplied'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ---------- Alumni Network ----------

  Future<Map<String, dynamic>> getAlumniMatches(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/alumni/match/$leadId'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> requestAlumniConnection({required String leadId, required String studentId}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/alumni/connect'),
      headers: _headers,
      body: jsonEncode({'lead_id': leadId, 'student_id': studentId}),
    );
    _checkOk(res, expected: 201);
  }

  Future<void> setAlumniAvailability(String studentId, {required bool available, String? bio}) async {
    final res = await http.put(
      Uri.parse('$baseUrl/alumni/availability/$studentId'),
      headers: _headers,
      body: jsonEncode({'available_for_contact': available, 'bio': bio}),
    );
    _checkOk(res);
  }

  // ---------- Payments ----------

  Future<Map<String, dynamic>> initiatePayment({required String feePaymentId, required String gateway}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/payments/initiate'),
      headers: _headers,
      body: jsonEncode({'fee_payment_id': feePaymentId, 'gateway': gateway}),
    );
    if (res.statusCode == 502 || res.statusCode == 400) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Payment could not be started');
    }
    _checkOk(res, expected: 201);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------- Predictions ----------

  Future<Map<String, dynamic>> getCollegePredictions(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/predictions/colleges/$leadId'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------- Compliance ----------

  Future<Map<String, dynamic>> getConsent(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/compliance/consent/$leadId'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> recordConsent({required String leadId, required String consentType, required bool granted, String? method}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/compliance/consent'),
      headers: _headers,
      body: jsonEncode({'lead_id': leadId, 'consent_type': consentType, 'granted': granted, 'method': method}),
    );
    _checkOk(res, expected: 201);
  }

  Future<Map<String, dynamic>> exportLeadData(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/compliance/export/$leadId'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> eraseLeadData(String leadId) async {
    final res = await http.delete(Uri.parse('$baseUrl/compliance/erase/$leadId'), headers: _headers, body: jsonEncode({'confirm': true}));
    _checkOk(res);
  }

  // ---------- Smart Triage ----------

  Future<Map<String, dynamic>> testTriage(String message, {String? leadId}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/triage/test'),
      headers: _headers,
      body: jsonEncode({'message': message, 'lead_id': leadId}),
    );
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPaymentStatus(String linkId) async {
    final res = await http.get(Uri.parse('$baseUrl/payments/status/$linkId'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifyKhaltiPayment(String linkId) async {
    final res = await http.get(Uri.parse('$baseUrl/payments/khalti/verify/$linkId'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getAlumniConnections() async {
    final res = await http.get(Uri.parse('$baseUrl/alumni/connections'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getDataRequests() async {
    final res = await http.get(Uri.parse('$baseUrl/compliance/requests'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getCollegeInsights() async {
    final res = await http.get(Uri.parse('$baseUrl/predictions/insights'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }


  // ---------- Calling Cockpit ----------

  Future<Map<String, dynamic>> getCockpit(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/cockpit/$leadId'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getNextBestAction(String leadId) async {
    final res = await http.post(Uri.parse('$baseUrl/cockpit/$leadId/next-best-action'), headers: _headers);
    if (res.statusCode == 502) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'AI not configured yet');
    }
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDraft(String leadId, {String channel = 'whatsapp'}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/cockpit/$leadId/draft'),
      headers: _headers,
      body: jsonEncode({'channel': channel}),
    );
    if (res.statusCode == 502) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'AI not configured yet');
    }
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> confirmCockpitSend({
    required String leadId,
    required String channel,
    required String draftText,
    String? contentId,
    String? sentBy,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/cockpit/$leadId/confirm-send'),
      headers: _headers,
      body: jsonEncode({
        'channel': channel,
        'draft_text': draftText,
        'content_id': contentId,
        'sent_by': sentBy ?? 'Counselor',
      }),
    );
    _checkOk(res, expected: 201);
  }

  Future<List<Map<String, dynamic>>> getOffers(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/cockpit/offers/$leadId'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> createOffer({
    required String leadId,
    required String offerText,
    num? amount,
    String? givenBy,
    String? notes,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/cockpit/offers'),
      headers: _headers,
      body: jsonEncode({
        'lead_id': leadId,
        'offer_text': offerText,
        'amount': amount,
        'given_by': givenBy ?? 'Counselor',
        'notes': notes,
      }),
    );
    _checkOk(res, expected: 201);
  }

  Future<void> updateOfferStatus(String offerId, String status) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/cockpit/offers/$offerId'),
      headers: _headers,
      body: jsonEncode({'status': status}),
    );
    _checkOk(res);
  }

  Future<List<Map<String, dynamic>>> getContentLibrary() async {
    final res = await http.get(Uri.parse('$baseUrl/cockpit/content'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getSendQueueToday() async {
    final res = await http.get(Uri.parse('$baseUrl/cockpit/send-queue/today'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }


  // ---------- Excel/CSV Custom Import + Export (Phase 2) ----------

  Future<Map<String, dynamic>> previewLeadsExcelImport(String filePath, String fileName) async {
    final uri = Uri.parse('$baseUrl/leads-excel/import/preview');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'x-tenant-id': tenantId})
      ..files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception(jsonDecode(body)['error'] ?? 'Could not read file');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> commitLeadsExcelImport(
    String filePath,
    String fileName,
    Map<String, String> mapping,
  ) async {
    final uri = Uri.parse('$baseUrl/leads-excel/import/commit');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'x-tenant-id': tenantId})
      ..fields['mapping'] = jsonEncode(mapping)
      ..files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 201) {
      throw Exception(jsonDecode(body)['error'] ?? 'Import failed');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  String buildLeadsExportUrl(List<String> columns) {
    final cols = Uri.encodeComponent(columns.join(','));
    return '$baseUrl/leads-excel/export?tenant_id=$tenantId&columns=$cols';
  }


  // ---------- WhatsApp API (paid, Phase 4 — only usable once Vinay has Meta credentials) ----------

  Future<bool> checkWhatsAppApiConfigured() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/whatsapp/status'), headers: _headers);
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['configured'] == true;
    } catch (_) {
      return false; // network hiccup — fail closed, never show a paid option that might not work
    }
  }

  Future<void> sendViaWhatsAppApi({required String leadId, required String message, String? createdBy}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/whatsapp/send'),
      headers: _headers,
      body: jsonEncode({'lead_id': leadId, 'message': message, 'created_by': createdBy ?? 'Counselor'}),
    );
    if (res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'WhatsApp API send failed');
    }
  }


  // ---------- Flyer Studio (Phase 5) ----------

  Future<Map<String, dynamic>> getFlyerTemplates() async {
    final res = await http.get(Uri.parse('$baseUrl/flyers/templates'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> generateFlyer({required String templateId, required Map<String, dynamic> fields}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/flyers/generate'),
      headers: _headers,
      body: jsonEncode({'template_id': templateId, 'fields': fields}),
    );
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Flyer generation failed');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> quickGenerateFlyer({required String templateId, String? leadId}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/flyers/quick-generate'),
      headers: _headers,
      body: jsonEncode({'template_id': templateId, 'lead_id': leadId}),
    );
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'AI flyer generation failed');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveFlyer({
    required String templateId,
    required Map<String, dynamic> fields,
    String? leadId,
    bool aiGenerated = false,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/flyers/save'),
      headers: _headers,
      body: jsonEncode({'template_id': templateId, 'fields': fields, 'lead_id': leadId, 'ai_generated': aiGenerated}),
    );
    if (res.statusCode != 201) throw Exception(jsonDecode(res.body)['error'] ?? 'Could not save flyer');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }


  // ---------- Lead Folders (Phase 6) ----------

  Future<List<Map<String, dynamic>>> getLeadFolders() async {
    final res = await http.get(Uri.parse('$baseUrl/leads-folders'), headers: _headers);
    _checkOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['folders'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getLeadsInFolder(String categoryId) async {
    final res = await http.get(Uri.parse('$baseUrl/leads-folders/$categoryId/leads'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> setLeadFolder(String leadId, String category) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/leads-folders/$leadId'),
      headers: _headers,
      body: jsonEncode({'category': category}),
    );
    _checkOk(res);
  }


  // ---------- Fees & Documents (Cockpit integration) ----------

  Future<Map<String, dynamic>> getFinanceSummary(String leadId) async {
    final res = await http.get(Uri.parse('$baseUrl/cockpit/$leadId/finance-summary'), headers: _headers);
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> markFeePaidFromCockpit({required String leadId, required String feeId, String? paymentMethod}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/cockpit/$leadId/mark-fee-paid'),
      headers: _headers,
      body: jsonEncode({'fee_id': feeId, 'payment_method': paymentMethod}),
    );
    _checkOk(res);
  }

  // ---------- Lead Detail Customization ----------

  Future<List<Map<String, dynamic>>> getLeadDetailSections() async {
    final res = await http.get(Uri.parse('$baseUrl/lead-detail-sections'), headers: _headers);
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> updateLeadDetailSection(String sectionKey, Map<String, dynamic> updates) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/lead-detail-sections/$sectionKey'),
      headers: _headers,
      body: jsonEncode(updates),
    );
    _checkOk(res);
    return jsonDecode(res.body);
  }

  Future<List<Map<String, dynamic>>> reorderLeadDetailSections(List<String> order) async {
    final res = await http.put(
      Uri.parse('$baseUrl/lead-detail-sections/reorder'),
      headers: _headers,
      body: jsonEncode({'order': order}),
    );
    _checkOk(res);
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  void _checkOk(http.Response res, {int expected = 200}) {
    if (res.statusCode != expected) {
      String message = 'Request failed (${res.statusCode})';
      try {
        message = jsonDecode(res.body)['error'] ?? message;
      } catch (_) {}
      throw Exception(message);
    }
  }
}
