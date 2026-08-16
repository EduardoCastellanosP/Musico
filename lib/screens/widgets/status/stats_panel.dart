import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/musician_stats.dart';

/// Performance snapshot fed by `contact_events` (today/this month) and the
/// musician's own `rating` column.
class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key, required this.stats, required this.rating});

  final MusicianStats stats;
  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.today_rounded,
            iconColor: AppColors.profileAccent,
            label: 'Contactos hoy',
            value: '${stats.contactsToday}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.calendar_month_rounded,
            iconColor: AppColors.profileAccent,
            label: 'Este mes',
            value: '${stats.contactsThisMonth}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            // Kept as the traditional gold rating star — every other accent
            // on this screen is the blue `profileAccent`.
            icon: Icons.star_rounded,
            iconColor: AppColors.accent,
            label: 'Rating',
            value: rating.toStringAsFixed(1),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: extension?.cardColor ?? theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark ? null : AppColors.lightCardShadow,
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
