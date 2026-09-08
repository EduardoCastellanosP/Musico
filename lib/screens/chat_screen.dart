import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../models/musician.dart';
import '../repositories/chat_repository.dart';
import '../repositories/musician_repository.dart';
import 'musician_detail_screen.dart';
import 'widgets/chat/share_contact_modal.dart';

/// Fixed dark-navy palette for [ChatScreen] — deliberately NOT
/// theme-adaptive (no light-mode variant): this screen always renders in
/// its own dark/blue identity regardless of the app's global light/dark
/// toggle, same as most modern chat surfaces.
abstract final class _ChatPalette {
  static const background = Color(0xFF081120);
  static const inputBar = Color(0xFF101C31);
  static const receivedBubble = Color(0xFF18263D);
  static const shareCard = Color(0xFF102338);
  static const border = Color(0xFF263A5A);
  static const appBarStart = Color(0xFF2563EB);
  static const appBarEnd = Color(0xFF1D4ED8);
  static const sentBubbleStart = Color(0xFF3B82F6);
  static const sentBubbleEnd = Color(0xFF2563EB);
  static const textSecondary = Color(0xFF94A3B8);
  static const textSecondaryLight = Color(0xFFCBD5E1);
  static const sentTimeColor = Color(0xFFBFDBFE);
  static const online = Color(0xFF22C55E);
}

/// 1:1 chat with [musician] — the app's only sanctioned way to exchange a
/// direct WhatsApp number or phone call contact (see `supabase/schema.sql`
/// section 14, "Chat interno"). Both sides text normally; either can also
/// push their own contact into the thread through the attach button's
/// "Compartir..." sheet, gated by [showShareContactModal]'s legal-consent
/// dialog.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.musician});

  final Musician musician;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatRepository _chatRepository = ChatRepository();
  final MusicianRepository _musicianRepository = MusicianRepository();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _conversationId;
  Musician? _myProfile;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final conversationFuture = _chatRepository.getOrCreateConversation(
        widget.musician.id,
      );
      final profileFuture = _musicianRepository.fetchCurrentProfile();
      final conversationId = await conversationFuture;
      final myProfile = await profileFuture;
      if (!mounted) return;
      setState(() {
        _conversationId = conversationId;
        _myProfile = myProfile;
      });
    } catch (e) {
      debugPrint('OPEN CHAT ERROR: $e');
      if (!mounted) return;
      setState(() => _error = 'No pudimos abrir el chat. Intenta de nuevo.');
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    final conversationId = _conversationId;
    if (text.isEmpty || conversationId == null || _sending) return;
    _textController.clear();
    setState(() => _sending = true);
    try {
      await _chatRepository.sendText(conversationId, text);
      _scrollToBottom();
    } catch (e) {
      debugPrint('SEND MESSAGE ERROR: $e');
      if (mounted) _showMessage('No pudimos enviar el mensaje.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Snaps back to the newest message — index 0 of the `reverse: true`
  /// list is the visual bottom, so animating to offset 0 is "scroll down".
  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _shareContact(ChatMessageType type) async {
    final conversationId = _conversationId;
    final myProfile = _myProfile;
    if (conversationId == null) return;
    if (myProfile == null || !myProfile.hasPhone) {
      _showMessage('Agrega tu número en "Mi Estado" antes de compartirlo.');
      return;
    }

    final accepted = await showShareContactModal(context, type: type);
    if (!accepted) return;

    final uri = type == ChatMessageType.whatsappShare
        ? myProfile.whatsappUri
        : myProfile.callUri;

    try {
      await _chatRepository.shareContact(
        conversationId: conversationId,
        type: type,
        content: uri.toString(),
      );
      _scrollToBottom();
    } catch (e) {
      debugPrint('SHARE CONTACT ERROR: $e');
      if (mounted) _showMessage('No pudimos compartir tu contacto.');
    }
  }

  /// Bottom sheet the paperclip button opens — the two contact-share
  /// actions live here (WhatsApp/Telegram-style "attach" picker) instead of
  /// in the app bar, since sharing a direct contact is the only thing this
  /// chat lets you "attach".
  Future<void> _openAttachSheet() async {
    final type = await showModalBottomSheet<ChatMessageType>(
      context: context,
      backgroundColor: _ChatPalette.inputBar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Compartir contacto',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _AttachSheetOption(
              icon: Icons.chat_rounded,
              iconColor: const Color(0xFF25D366),
              label: 'Compartir mi WhatsApp',
              onTap: () =>
                  Navigator.of(context).pop(ChatMessageType.whatsappShare),
            ),
            _AttachSheetOption(
              icon: Icons.call_rounded,
              iconColor: _ChatPalette.sentBubbleStart,
              label: 'Compartir mi número para llamadas',
              onTap: () => Navigator.of(context).pop(ChatMessageType.callShare),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (type != null) await _shareContact(type);
  }

  void _openMusicianProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MusicianDetailScreen(musician: widget.musician),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ChatPalette.background,
      appBar: _ChatAppBar(
        musician: widget.musician,
        onTapProfile: _openMusicianProfile,
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          _ChatInputBar(
            controller: _textController,
            sending: _sending,
            onSend: _sendText,
            onAttach: _openAttachSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ChatPalette.textSecondaryLight),
          ),
        ),
      );
    }
    final conversationId = _conversationId;
    if (conversationId == null) {
      return const Center(
        child: CircularProgressIndicator(color: _ChatPalette.sentBubbleStart),
      );
    }
    return StreamBuilder<List<ChatMessage>>(
      stream: _chatRepository.watchMessages(conversationId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'No pudimos cargar los mensajes.',
              style: TextStyle(color: _ChatPalette.textSecondaryLight),
            ),
          );
        }
        final messages = snapshot.data;
        if (messages == null) {
          return const Center(
            child: CircularProgressIndicator(
              color: _ChatPalette.sentBubbleStart,
            ),
          );
        }
        if (messages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Empieza la conversación con ${widget.musician.fullName}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _ChatPalette.textSecondary),
              ),
            ),
          );
        }
        final reversed = messages.reversed.toList();
        final myId = _chatRepository.currentUserId;
        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          itemCount: reversed.length,
          itemBuilder: (context, index) {
            final message = reversed[index];
            return _MessageBubble(
              key: ValueKey(message.id),
              message: message,
              isMine: message.isMine(myId),
            );
          },
        );
      },
    );
  }
}

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ChatAppBar({required this.musician, required this.onTapProfile});

  final Musician musician;
  final VoidCallback onTapProfile;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 4);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: preferredSize.height,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_ChatPalette.appBarStart, _ChatPalette.appBarEnd],
          ),
        ),
      ),
      titleSpacing: 0,
      title: InkWell(
        onTap: onTapProfile,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              _AppBarAvatar(musician: musician),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      musician.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // No hay presencia en tiempo real todavía — se
                      // aproxima con el estado "disponible" que el músico ya
                      // reporta en Mi Estado, igual que hace MusicianCard.
                      musician.isFree ? 'En línea' : 'Desconectado',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: musician.isFree
                            ? _ChatPalette.online
                            : Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: onTapProfile,
          icon: const Icon(Icons.more_vert_rounded),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _AppBarAvatar extends StatelessWidget {
  const _AppBarAvatar({required this.musician});

  final Musician musician;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = musician.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
            child: hasAvatar
                ? null
                : Text(
                    musician.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
          ),
          if (musician.isFree)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _ChatPalette.online,
                  border: Border.all(
                    color: _ChatPalette.appBarEnd,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fades + slides a bubble in once when it first appears — [key] on the
/// `ValueKey(message.id)` the caller passes is what lets Flutter recognize
/// already-seen messages across rebuilds so only genuinely new ones replay
/// this, instead of the whole list flashing on every incoming message.
class _MessageBubble extends StatefulWidget {
  const _MessageBubble({super.key, required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.message.type != ChatMessageType.text
        ? _ContactShareCard(message: widget.message, isMine: widget.isMine)
        : _TextBubble(message: widget.message, isMine: widget.isMine);

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: content),
    );
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          gradient: isMine
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _ChatPalette.sentBubbleStart,
                    _ChatPalette.sentBubbleEnd,
                  ],
                )
              : null,
          color: isMine ? null : _ChatPalette.receivedBubble,
          borderRadius: BorderRadius.circular(18),
          border: isMine
              ? null
              : Border.all(color: _ChatPalette.border.withValues(alpha: 0.5)),
          boxShadow: isMine
              ? [
                  BoxShadow(
                    color: _ChatPalette.sentBubbleEnd.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 5),
            _MessageMeta(createdAt: message.createdAt, isMine: isMine),
          ],
        ),
      ),
    );
  }
}

class _MessageMeta extends StatelessWidget {
  const _MessageMeta({required this.createdAt, required this.isMine});

  final DateTime createdAt;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final color = isMine ? _ChatPalette.sentTimeColor : _ChatPalette.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_formatTime(createdAt), style: TextStyle(fontSize: 11.5, color: color)),
        if (isMine) ...[
          const SizedBox(width: 4),
          // Doble check = "enviado": no hay recibos de lectura en el
          // esquema todavía, así que esto no distingue leído/no leído.
          Icon(Icons.done_all_rounded, size: 14, color: color),
        ],
      ],
    );
  }

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

/// Redesigned whatsapp_share/call_share card — belongs visually to MUSSY's
/// blue chat language; only the small leading icon badge borrows the
/// contact method's own brand color (WhatsApp green / call blue).
class _ContactShareCard extends StatelessWidget {
  const _ContactShareCard({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final isWhatsapp = message.type == ChatMessageType.whatsappShare;
    final title = isWhatsapp
        ? 'Compartió su WhatsApp'
        : 'Compartió su número para llamadas';
    final subtitle = isWhatsapp
        ? 'Inicia la conversación en WhatsApp'
        : 'Puedes llamarlo directamente';
    final buttonLabel = isWhatsapp ? 'Abrir WhatsApp' : 'Llamar ahora';
    final icon = isWhatsapp ? Icons.chat_rounded : Icons.call_rounded;
    final iconAccent = isWhatsapp
        ? const Color(0xFF25D366)
        : _ChatPalette.sentBubbleStart;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: _ChatPalette.shareCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _ChatPalette.sentBubbleStart.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconAccent.withValues(alpha: 0.16),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: iconAccent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _ChatPalette.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => launchUrl(
                  Uri.parse(message.content),
                  mode: LaunchMode.externalApplication,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _ChatPalette.sentBubbleStart,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      buttonLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachSheetOption extends StatelessWidget {
  const _AttachSheetOption({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: iconColor.withValues(alpha: 0.16),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 19, color: iconColor),
      ),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _ChatPalette.inputBar,
            borderRadius: BorderRadius.circular(29),
            border: Border.all(color: _ChatPalette.border.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _AttachButton(onTap: onAttach),
              const SizedBox(width: 4),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120, minHeight: 42),
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    cursorColor: _ChatPalette.sentBubbleStart,
                    decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      hintStyle: TextStyle(
                        color: _ChatPalette.textSecondary,
                        fontSize: 16,
                      ),
                      filled: false,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _SendButton(controller: controller, sending: sending, onSend: onSend),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(
            Icons.attach_file_rounded,
            size: 20,
            color: _ChatPalette.textSecondaryLight,
          ),
        ),
      ),
    );
  }
}

/// Dims to ~50% opacity while [controller] is empty, full opacity once
/// there's text to send — `TextEditingController` is already a
/// `ValueNotifier`, so this needs no extra state of its own.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: hasText ? 1 : 0.5,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: Ink(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _ChatPalette.sentBubbleStart,
                    _ChatPalette.sentBubbleEnd,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x552563EB),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: InkWell(
                onTap: sending ? null : onSend,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: Center(
                    child: sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
