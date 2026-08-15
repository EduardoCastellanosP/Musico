import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

const int kStatusMessageMaxLength = 120;

/// Free-text status message shown on the musician's dashboard card, with a
/// live "42/120" counter (Flutter's built-in [TextField.maxLength] counter).
class MessageFieldCard extends StatelessWidget {
  const MessageFieldCard({super.key, required this.controller});

  final TextEditingController controller;

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
            'Mensaje de estado',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Cuéntale a los contratantes algo extra.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            maxLength: kStatusMessageMaxLength,
            maxLines: 3,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'Ej: Disponible para parrandas y eventos privados',
            ),
          ),
        ],
      ),
    );
  }
}
