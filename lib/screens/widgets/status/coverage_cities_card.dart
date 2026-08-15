import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Editable list of extra municipalities the musician travels to, beyond
/// their base city — feeds `profiles.coverage_cities` and the dashboard's
/// coverage-aware search.
class CoverageCitiesCard extends StatelessWidget {
  const CoverageCitiesCard({
    super.key,
    required this.cities,
    required this.inputController,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> cities;
  final TextEditingController inputController;
  final VoidCallback onAdd;
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: inputController,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => onAdd(),
                  style: theme.textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: 'Ej: Floridablanca',
                    prefixIcon: Icon(Icons.add_location_alt_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: onAdd,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.all(14),
                ),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
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
