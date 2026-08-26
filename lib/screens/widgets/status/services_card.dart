import 'package:flutter/material.dart';

import '../../../core/constants/services.dart';
import '../../../core/theme/app_theme.dart';
import 'multi_select_search_field.dart';

/// "Servicios" — lets a profile offer more than one thing at once (e.g.
/// "Músico" and "Sonido"). Selecting it drives which sections
/// [StatusScreen] shows next: [MusicianSkillsCard] for "Músico", a free-text
/// inventory field for any technical service.
class ServicesCard extends StatelessWidget {
  const ServicesCard({
    super.key,
    required this.selectedServices,
    required this.onChanged,
  });

  final List<String> selectedServices;
  final ValueChanged<List<String>> onChanged;

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
            'Servicios',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '¿Qué ofreces? Puedes marcar varios, por ejemplo Músico y Sonido.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          MultiSelectSearchField(
            options: MusicianServices.all,
            selected: selectedServices,
            onChanged: onChanged,
            addLabel: 'Agregar servicio',
            searchHint: 'Busca un servicio...',
          ),
        ],
      ),
    );
  }
}
