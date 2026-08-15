import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Prompted by the dashboard's availability assistant when a musician's
/// `busy_until` cutoff has passed while they were still marked "ocupado".
/// Returns `true` for "sí, ya estoy libre", `false` for "no, sigo ocupado",
/// or `null` if dismissed without a choice.
class AutoCheckoutDialog extends StatelessWidget {
  const AutoCheckoutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return AlertDialog(
      backgroundColor: extension?.cardColor ?? theme.cardColor,
      icon: const Icon(
        Icons.event_available_rounded,
        color: AppColors.accent,
        size: 32,
      ),
      title: const Text('¿Sigues ocupado?', textAlign: TextAlign.center),
      content: const Text(
        '¿Ya terminaste tu toque y estás libre de nuevo?',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('No, sigo ocupado'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sí, ya estoy libre'),
        ),
      ],
    );
  }
}
