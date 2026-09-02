import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Free-text description field, shown for every role but with a title/hint
/// tailored to it — years of experience and bands played for a "Músico",
/// sound/lighting inventory for a technical service, amenities for a
/// rehearsal space or stage rental, or both at once when a profile offers
/// more than one. [title] mirrors [Musician.descriptionSectionTitle] so
/// this card and [MusicianDetailScreen]'s read-only view always agree on
/// what to call the field for a given role mix.
class ServiceInventoryCard extends StatelessWidget {
  const ServiceInventoryCard({
    super.key,
    required this.controller,
    required this.title,
    required this.hint,
  });

  final TextEditingController controller;
  final String title;
  final String hint;

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
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Esto es lo primero que leen los contratantes en tu perfil público.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            maxLines: 6,
            minLines: 3,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: hint,
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}
