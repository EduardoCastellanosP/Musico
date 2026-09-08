import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/chat_message.dart';

/// High-priority legal disclaimer shown before "Compartir mi WhatsApp" /
/// "Compartir mi número para llamadas" actually posts the contact link into
/// the chat. Returns `true` only when the user taps "Acepto y Compartir" —
/// Cancelar or dismissing the dialog returns `false` and nothing is sent.
Future<bool> showShareContactModal(
  BuildContext context, {
  required ChatMessageType type,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _ShareContactDialog(type: type),
  );
  return result ?? false;
}

class _ShareContactDialog extends StatelessWidget {
  const _ShareContactDialog({required this.type});

  final ChatMessageType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final label = type == ChatMessageType.whatsappShare
        ? 'tu WhatsApp'
        : 'tu número para llamadas';

    return AlertDialog(
      backgroundColor: extension?.cardColor ?? theme.cardColor,
      icon: const Icon(
        Icons.warning_amber_rounded,
        color: AppColors.accent,
        size: 32,
      ),
      title: const Text(
        'Vas a compartir un contacto directo',
        textAlign: TextAlign.center,
      ),
      content: Text(
        'Al compartir $label, cualquier negociación, trato económico o '
        'contrato que hagas fuera de MUSSY queda bajo tu absoluta y '
        'exclusiva responsabilidad personal.\n\n'
        'MUSSY actúa únicamente como un directorio de conexión entre '
        'músicos y contratantes, y queda liberada de cualquier '
        'responsabilidad ante fraudes, incumplimientos, disputas o '
        'cualquier eventualidad ocurrida fuera del entorno digital de la '
        'aplicación.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: extension?.textSecondary,
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Acepto y Compartir'),
        ),
      ],
    );
  }
}
