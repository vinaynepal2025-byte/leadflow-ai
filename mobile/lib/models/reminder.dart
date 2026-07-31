class ReminderItem {
  final String id;
  final String leadId;
  final String title;
  final String dueAt;
  final String status;
  final String? assignedTo;

  ReminderItem({
    required this.id,
    required this.leadId,
    required this.title,
    required this.dueAt,
    required this.status,
    this.assignedTo,
  });

  factory ReminderItem.fromJson(Map<String, dynamic> json) {
    return ReminderItem(
      id: json['id'] as String,
      leadId: json['lead_id'] as String,
      title: json['title'] as String,
      dueAt: json['due_at'] as String,
      status: json['status'] as String,
      assignedTo: json['assigned_to'] as String?,
    );
  }
}
