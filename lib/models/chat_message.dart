/// Wire values match the `message_type` CHECK constraint on `messages` —
/// see `supabase/schema.sql` section 14 ("Chat interno").
enum ChatMessageType {
  text,
  whatsappShare,
  callShare;

  static ChatMessageType fromWire(String value) {
    switch (value) {
      case 'whatsapp_share':
        return ChatMessageType.whatsappShare;
      case 'call_share':
        return ChatMessageType.callShare;
      default:
        return ChatMessageType.text;
    }
  }

  String get wireValue => switch (this) {
    ChatMessageType.text => 'text',
    ChatMessageType.whatsappShare => 'whatsapp_share',
    ChatMessageType.callShare => 'call_share',
  };
}

/// A row of the Supabase `messages` table.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.type,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      type: ChatMessageType.fromWire(
        json['message_type'] as String? ?? 'text',
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final ChatMessageType type;
  final DateTime createdAt;

  bool isMine(String? currentUserId) => senderId == currentUserId;
}
