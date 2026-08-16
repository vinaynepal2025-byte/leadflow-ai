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

  // Added for the Pipeline Board's optimistic drag-and-drop stage moves:
  // updating local state needs a way to produce "this lead, but in a
  // different stage" without a round-trip refetch, so the card can jump
  // to its new column the instant the drag completes.
  Lead copyWith({
    String? id,
    String? tenantId,
    String? fullName,
    String? phone,
    String? email,
    String? source,
    String? stage,
    String? assignedTo,
    String? notes,
    String? parentName,
    String? parentPhone,
    Map<String, dynamic>? customFields,
    String? createdAt,
    String? updatedAt,
  }) {
    return Lead(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      source: source ?? this.source,
      stage: stage ?? this.stage,
      assignedTo: assignedTo ?? this.assignedTo,
      notes: notes ?? this.notes,
      parentName: parentName ?? this.parentName,
      parentPhone: parentPhone ?? this.parentPhone,
      customFields: customFields ?? this.customFields,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// Pipeline stages are now tenant-defined via the Pipeline Builder
// (see /pipeline-stages API + pipeline_builder_screen.dart) rather than
// hardcoded here.
