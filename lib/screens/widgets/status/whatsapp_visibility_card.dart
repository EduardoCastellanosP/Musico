import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// "Poner mi WhatsApp público" — lets a musician opt into showing a direct
/// WhatsApp button on their [MusicianCard] (see `supabase/schema.sql`
/// section 15) instead of only the internal chat. Turning it ON is gated
/// by [showWhatsappLiabilityWaiver]'s consent dialog; the switch here never
/// flips optimistically for that direction — [onAccepted] only fires after
/// the user taps "Acepto y Activar". Turning it OFF needs no confirmation.
class WhatsappVisibilityCard extends StatelessWidget {
  const WhatsappVisibilityCard({
    super.key,
    required this.value,
    required this.onRequestEnable,
    required this.onDisable,
  });

  final bool value;

  /// Called when the user drags the switch to ON — must show the consent
  /// dialog and only actually persist `show_whatsapp = true` if accepted.
  final VoidCallback onRequestEnable;

  /// Called when the user drags the switch to OFF — no modal required.
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: extension?.cardColor ?? theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? null : AppColors.lightCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.fromLTRB(18, 4, 14, 4),
        title: const Text(
          'Poner mi WhatsApp público',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          value
              ? 'Tu WhatsApp aparece como botón directo en tu tarjeta.'
              : 'Solo te podrán contactar por el chat interno de MUSSY.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: extension?.textSecondary,
          ),
        ),
        value: value,
        onChanged: (turningOn) =>
            turningOn ? onRequestEnable() : onDisable(),
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.profileAccent,
      ),
    );
  }
}

/// The liability-waiver `AlertDialog` — returns `true` only when the user
/// taps "Acepto y Activar". Cancelar or dismissing returns `false`, and the
/// caller must leave `show_whatsapp`/the switch untouched in that case.
Future<bool> showWhatsappLiabilityWaiver(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => const _WhatsappLiabilityWaiverDialog(),
  );
  return accepted ?? false;
}

class _WhatsappLiabilityWaiverDialog extends StatelessWidget {
  const _WhatsappLiabilityWaiverDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return AlertDialog(
      backgroundColor: extension?.cardColor ?? theme.cardColor,
      icon: const Icon(
        Icons.gavel_rounded,
        color: AppColors.profileAccent,
        size: 32,
      ),
      title: const Text(
        'Antes de hacer público tu WhatsApp',
        textAlign: TextAlign.center,
      ),
      content: Text(
        'Las negociaciones, acuerdos económicos, contrataciones y tratos '
        'que hagas con otros usuarios se realizan bajo tu absoluta y '
        'exclusiva responsabilidad personal.\n\n'
        'MUSSY actúa únicamente como un directorio digital de conexión y '
        'queda completamente exenta de cualquier responsabilidad ante '
        'fraudes, incumplimientos, daños o eventualidades ocurridas fuera '
        'del entorno de la aplicación.',
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
            backgroundColor: AppColors.profileAccent,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Acepto y Activar'),
        ),
      ],
    );
  }
}
