import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'city_picker_sheet.dart';

/// Editable list of extra municipalities the musician travels to, beyond
/// their base city — feeds `profiles.coverage_cities` and the dashboard's
/// coverage-aware search.
class CoverageCitiesCard extends StatelessWidget {
  const CoverageCitiesCard({
    super.key,
    required this.cities,
    required this.onAddCity,
    required this.onRemove,
  });

  final List<String> cities;
  final ValueChanged<String> onAddCity;
  final ValueChanged<String> onRemove;

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
            'Cobertura de viaje',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Además de tu ciudad base, ¿a qué municipios te desplazas a tocar?',
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final selected = await showCityPickerSheet(
                context,
                title: 'Agregar municipio de cobertura',
              );
              if (selected != null) onAddCity(selected);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: extension?.inputFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.profileAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.add_location_alt_outlined,
                    color: AppColors.profileAccent,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Agregar municipio',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.profileAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (cities.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Aún no agregas municipios de cobertura.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: extension?.textSecondary,
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final city in cities)
                  Chip(
                    label: Text(city),
                    onDeleted: () => onRemove(city),
                    backgroundColor: extension?.inputFill,
                    deleteIconColor: extension?.textSecondary,
                    side: BorderSide.none,
                    labelStyle: theme.textTheme.bodyMedium,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
