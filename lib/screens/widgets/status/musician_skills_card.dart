import 'package:flutter/material.dart';

import '../../../core/constants/genres.dart';
import '../../../core/constants/instruments.dart';
import '../../../core/theme/app_theme.dart';
import 'multi_select_search_field.dart';

/// "Instrumentos" and "Género musical" — multi-selection chip pickers, only
/// shown while the musician offers the "Músico" service (see
/// [Musician.offersMusicianService]/[MusicianServices.musician]).
class MusicianSkillsCard extends StatelessWidget {
  const MusicianSkillsCard({
    super.key,
    required this.selectedInstruments,
    required this.onInstrumentsChanged,
    required this.selectedGenres,
    required this.onGenresChanged,
  });

  final List<String> selectedInstruments;
  final ValueChanged<List<String>> onInstrumentsChanged;
  final List<String> selectedGenres;
  final ValueChanged<List<String>> onGenresChanged;

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
            'Instrumentos y géneros',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Puedes elegir más de uno.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Instrumento',
            style: theme.textTheme.labelLarge?.copyWith(
              color: extension?.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          MultiSelectSearchField(
            options: VallenatoInstruments.all,
            selected: selectedInstruments,
            onChanged: onInstrumentsChanged,
            addLabel: 'Agregar instrumento',
            searchHint: 'Busca un instrumento...',
          ),
          const SizedBox(height: 18),
          Text(
            'Género musical',
            style: theme.textTheme.labelLarge?.copyWith(
              color: extension?.textSecondary,
              fontWeight: FontWeight.w600,
              
            ),
          ),
          const SizedBox(height: 8),
          MultiSelectSearchField(
            options: MusicGenres.all,
            selected: selectedGenres,
            onChanged: onGenresChanged,
            addLabel: 'Agregar género',
            searchHint: 'Busca un género...',
          ),
        ],
      ),
    );
  }
}
