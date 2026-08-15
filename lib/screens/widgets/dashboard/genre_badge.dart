import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Small pill showing a musician's genre — gold for Vallenato, teal for
/// Tropical. Shared between [MusicianCard] and the musician detail screen.
class GenreBadge extends StatelessWidget {
  const GenreBadge({super.key, required this.genre});

  final String genre;

  @override
  Widget build(BuildContext context) {
    if (genre.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = genre == 'Tropical' ? Colors.teal : AppColors.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        genre,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
