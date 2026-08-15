import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Small pill showing a musician's genre(s) — gold for Vallenato, teal for
/// Tropical, accent for anything else. Shows the first genre plus a "+N"
/// suffix when the musician performs more than one. Shared between
/// [MusicianCard] and the musician detail screen.
class GenreBadge extends StatelessWidget {
  const GenreBadge({super.key, required this.genres});

  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    if (genres.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final primaryGenre = genres.first;
    final color = primaryGenre == 'Tropical' ? Colors.teal : AppColors.accent;
    final label = genres.length > 1
        ? '$primaryGenre +${genres.length - 1}'
        : primaryGenre;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
