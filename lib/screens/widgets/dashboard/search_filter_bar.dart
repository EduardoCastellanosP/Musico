import 'package:flutter/material.dart';

import '../../../core/constants/genres.dart';
import '../../../core/constants/instruments.dart';
import '../../../core/constants/services.dart';
import '../../../core/theme/app_theme.dart';

/// Search field + genre/instrument/service chip rows + "solo libres" and
/// "toda Colombia" switches. Every change here triggers a fresh,
/// server-side filtered query — nothing is filtered from a locally cached
/// full list.
class SearchFilterBar extends StatelessWidget {
  const SearchFilterBar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.selectedGenre,
    required this.onGenreSelected,
    required this.selectedInstrument,
    required this.onInstrumentSelected,
    required this.selectedService,
    required this.onServiceSelected,
    required this.onlyFree,
    required this.onOnlyFreeChanged,
    required this.searchNationwide,
    required this.onNationwideChanged,
    this.homeCity,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String? selectedGenre;
  final ValueChanged<String?> onGenreSelected;
  final String? selectedInstrument;
  final ValueChanged<String?> onInstrumentSelected;
  final String? selectedService;
  final ValueChanged<String?> onServiceSelected;
  final bool onlyFree;
  final ValueChanged<bool> onOnlyFreeChanged;

  /// Requirement 4: when `false` (default) the directory only shows
  /// musicians near [homeCity]; when `true` it lists the whole country.
  final bool searchNationwide;
  final ValueChanged<bool> onNationwideChanged;

  /// The logged-in musician's own base city, used purely to label the
  /// "Cercanías" switch (e.g. "Cerca de Valledupar") — the actual filtering
  /// happens server-side in `MusicianRepository.fetchMusicians`.
  final String? homeCity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'Buscar por nombre, ciudad, instrumento o servicio',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel('Género'),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // _FilterChip(
                //   label: 'Todos',
                //   selected: selectedGenre == null,
                //   onTap: () => onGenreSelected(null),
                // ),
                for (final genre in MusicGenres.all)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _FilterChip(
                      label: genre,
                      selected: selectedGenre == genre,
                      onTap: () => onGenreSelected(genre),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionLabel('Instrumento'),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: 'Todos',
                  selected: selectedInstrument == null,
                  onTap: () => onInstrumentSelected(null),
                ),
                for (final instrument in VallenatoInstruments.all)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _FilterChip(
                      label: instrument,
                      selected: selectedInstrument == instrument,
                      onTap: () => onInstrumentSelected(instrument),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionLabel('Servicios'),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // _FilterChip(
                //   label: 'Todos',
                //   selected: selectedService == null,
                //   onTap: () => onServiceSelected(null),
                // ),
                for (final service in MusicianServices.all)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _FilterChip(
                      label: service,
                      selected: selectedService == service,
                      onTap: () => onServiceSelected(service),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: onlyFree,
            onChanged: onOnlyFreeChanged,
            activeThumbColor: AppColors.accent,
            title: Text(
              'Solo músicos libres',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: extension?.textSecondary,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: searchNationwide,
            onChanged: onNationwideChanged,
            activeThumbColor: AppColors.accent,
            title: Text(
              'Buscar en toda Colombia',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: extension?.textSecondary,
              ),
            ),
            subtitle: Text(
              searchNationwide
                  ? 'Mostrando músicos de todo el país.'
                  : (homeCity != null && homeCity!.isNotEmpty)
                  ? 'Mostrando músicos cerca de $homeCity.'
                  : 'Mostrando músicos cerca de tu ciudad.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: extension?.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: extension?.textSecondary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      backgroundColor: extension?.cardColor,
      selectedColor: AppColors.accent,
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: selected ? Colors.black : extension?.textSecondary,
      ),
      side: BorderSide(
        color: selected
            ? Colors.transparent
            : (extension?.textSecondary.withValues(alpha: 0.25) ?? Colors.grey),
      ),
    );
  }
}
