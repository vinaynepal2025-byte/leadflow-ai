class Communication {
  final String id;
  final String leadId;
  final String channel; // call | whatsapp | whatsapp-link | email | sms | note
  final String direction; // inbound | outbound
  final String? body;
  final String? createdBy;
  final String createdAt;

  Communication({
    required this.id,
    required this.leadId,
    required this.channel,
    required this.direction,
    this.body,
    this.createdBy,
    required this.createdAt,
  });

  factory Communication.fromJson(Map<String, dynamic> json) {
    return Communication(
      id: json['id'] as String,
      leadId: json['lead_id'] as String,
      channel: json['channel'] as String,
      direction: json['direction'] as String,
      body: json['body'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] as String,
    );
  }
}

class AiInsight {
  final String summary;
  final String sentiment;
  final String buyingIntent;
  final List<String> riskFlags;
  final String suggestedNextAction;
  final String suggestedWhatsappReply;

  AiInsight({
    required this.summary,
    required this.sentiment,
    required this.buyingIntent,
    required this.riskFlags,
    required this.suggestedNextAction,
    required this.suggestedWhatsappReply,
  });

  factory AiInsight.fromJson(Map<String, dynamic> json) {
    return AiInsight(
      summary: json['summary'] as String? ?? '',
      sentiment: json['sentiment'] as String? ?? 'neutral',
      buyingIntent: json['buying_intent'] as String? ?? 'medium',
      riskFlags: (json['risk_flags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      suggestedNextAction: json['suggested_next_action'] as String? ?? '',
      suggestedWhatsappReply: json['suggested_whatsapp_reply'] as String? ?? '',
    );
  }
}
