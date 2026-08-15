import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Free-text "Inventario / Descripción del Servicio" field, shown whenever
/// the musician offers a technical service (sound, rehearsal space, etc.).
/// Kept separate from [MusicianSkillsCard] since a profile can offer a
/// technical service with or without also being a "Músico".
class ServiceInventoryCard extends StatelessWidget {
  const ServiceInventoryCard({super.key, required this.controller});

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
            'Inventario / Descripción del servicio',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Cuéntale a los contratantes qué equipo o espacio ofreces.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            maxLines: 5,
            minLines: 3,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText:
                  'Ej: 2 cabinas activas de 15", consola de 12 canales, '
                  'micrófonos inalámbricos. Sala insonorizada con batería, '
                  'bajo y teclado incluidos.',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}
