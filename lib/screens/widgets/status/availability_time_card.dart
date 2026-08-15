import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Dynamic availability section: while the musician is "libre" it asks in
/// free text when they usually play; the moment they flip to "ocupado" it
/// swaps to the two native [showTimePicker] fields that define exactly when
/// today's gig starts and ends.
class AvailabilityTimeCard extends StatelessWidget {
  const AvailabilityTimeCard({
    super.key,
    required this.isFree,
    required this.availabilityNoteController,
    required this.from,
    required this.to,
    required this.onPickFrom,
    required this.onPickTo,
  });

  final bool isFree;
  final TextEditingController availabilityNoteController;
  final TimeOfDay from;
  final TimeOfDay to;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: extension?.cardColor ?? theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? null : AppColors.lightCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Franja horaria',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isFree
                ? 'Cuándo sueles estar disponible para tocar.'
                : 'A qué hora empieza y termina tu toque de hoy.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          if (isFree)
            TextField(
              controller: availabilityNoteController,
              maxLines: 2,
              style: theme.textTheme.bodyLarge,
              decoration: const InputDecoration(
                hintText:
                    '¿Cuándo estás disponible para tocar? '
                    'Ej: Fines de semana desde las 6:00 PM',
                prefixIcon: Icon(Icons.event_available_outlined),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: '¿Desde qué hora empiezas a tocar?',
                    time: from,
                    onTap: onPickFrom,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeField(
                    label: '¿A qué hora te desocupas?',
                    time: to,
                    onTap: onPickTo,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: extension?.inputFill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: extension?.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  time.format(context),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: AppColors.accent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
