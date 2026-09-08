import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';

/// Every read/write the internal chat performs against the `conversations`
/// and `messages` tables goes through here — see `supabase/schema.sql`
/// section 14 ("Chat interno").
class ChatRepository {
  ChatRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Opens (or reuses) the 1:1 conversation with [otherUserId] via the
  /// `get_or_create_conversation` RPC, which normalizes participant order
  /// so both sides always resolve to the same row.
  Future<String> getOrCreateConversation(String otherUserId) async {
    final id = await _client.rpc(
      'get_or_create_conversation',
      params: {'other_user_id': otherUserId},
    );
    return id as String;
  }

  /// Live message list for [conversationId], oldest first — backed by
  /// Supabase Realtime so new messages (including contact-share messages)
  /// appear without a manual refresh.
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        // postgrest-dart defaults `ascending` to false (newest first) —
        // explicit here since ChatScreen relies on oldest-first before it
        // reverses the list for its `reverse: true` ListView.
        .order('created_at', ascending: true)
        .map((rows) => rows.map(ChatMessage.fromJson).toList());
  }

  Future<void> sendText(String conversationId, String content) => _insert(
    conversationId: conversationId,
    content: content,
    type: ChatMessageType.text,
  );

  /// Inserts the special contact-share message the "Compartir mi
  /// WhatsApp"/"Compartir mi número para llamadas" consent flow produces.
  /// [content] is the full `https://wa.me/...` or `tel:...` link the other
  /// participant taps to reach out directly.
  Future<void> shareContact({
    required String conversationId,
    required ChatMessageType type,
    required String content,
  }) => _insert(conversationId: conversationId, content: content, type: type);

  Future<void> _insert({
    required String conversationId,
    required String content,
    required ChatMessageType type,
  }) async {
    final me = currentUserId;
    if (me == null) throw StateError('No hay una sesión activa.');
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': me,
      'content': content,
      'message_type': type.wireValue,
    });
  }
}
