class Lead {
  final String id;
  final String tenantId;
  final String fullName;
  final String? phone;
  final String? email;
  final String? source;
  final String stage;
  final String? assignedTo;
  final String? notes;
  final String? parentName;
  final String? parentPhone;
  final Map<String, dynamic> customFields;
  final String createdAt;
  final String updatedAt;

  Lead({
    required this.id,
    required this.tenantId,
    required this.fullName,
    this.phone,
    this.email,
    this.source,
    required this.stage,
    this.assignedTo,
    this.notes,
    this.parentName,
    this.parentPhone,
    this.customFields = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory Lead.fromJson(Map<String, dynamic> json) {
    return Lead(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      source: json['source'] as String?,
      stage: json['stage'] as String,
      assignedTo: json['assigned_to'] as String?,
      notes: json['notes'] as String?,
      parentName: json['parent_name'] as String?,
      parentPhone: json['parent_phone'] as String?,
      customFields: json['custom_fields'] is Map ? Map<String, dynamic>.from(json['custom_fields']) : {},
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }
}

// Pipeline stages are now tenant-defined via the Pipeline Builder
// (see /pipeline-stages API + pipeline_builder_screen.dart) rather than
// hardcoded here.
