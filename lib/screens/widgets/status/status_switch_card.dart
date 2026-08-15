import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Big Libre/Ocupado toggle at the top of "Mi Estado" — this single switch
/// is what the dashboard's status dots and availability count read from.
class StatusSwitchCard extends StatelessWidget {
  const StatusSwitchCard({
    super.key,
    required this.isFree,
    required this.onChanged,
  });

  final bool isFree;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = isFree ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: extension?.cardColor ?? theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? null : AppColors.lightCardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isFree
                  ? Icons.check_circle_rounded
                  : Icons.do_not_disturb_on_rounded,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFree ? 'Estás libre' : 'Estás ocupado',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  isFree
                      ? 'Los contratantes pueden verte disponible.'
                      : 'No aparecerás como disponible ahora.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: extension?.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isFree,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.green,
            inactiveTrackColor: Colors.red.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}
