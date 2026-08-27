import 'package:flutter/material.dart';

import '../../../core/constants/genres.dart';
import '../../../core/constants/instruments.dart';
import '../../../core/constants/services.dart';
import '../../../core/security/input_sanitizer.dart'; // 🔒 FASE 3: Sanitización de entradas
import '../../../core/theme/app_theme.dart';
import '../status/city_picker_sheet.dart';

/// Search field + genre/instrument/service pickers + "solo libres" and
/// "solo mi ciudad" switches. Every change here triggers a fresh,
/// server-side filtered query — nothing is filtered from a locally cached
/// full list. Visual only: same props, same callbacks, same selection
/// state as before.
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
    required this.selectedCityFilter,
    required this.onCityFilterSelected,
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

  /// Explicit "search this city" filter (e.g. "Valledupar"), independent of
  /// [homeCity]/[searchNationwide] — set via [showCityPickerSheet]. When
  /// non-null, [DashboardScreen] passes it as `fetchMusicians`'s `nearCity`
  /// (with `searchNationwide: false`), so it gets the exact same
  /// `CityZones` widening the "Cercanías" default already uses: a musician
  /// based in a nearby commuter town still shows up, not just exact matches.
  final String? selectedCityFilter;
  final ValueChanged<String?> onCityFilterSelected;

  /// The logged-in musician's own base city, used purely to label the
  /// "Solo mi ciudad" switch and the caption below it — the actual
  /// filtering happens server-side in `MusicianRepository.fetchMusicians`.
  final String? homeCity;

  /// Opens the bottom sheet for one category (Género/Instrumento/Servicios).
  void _openCategorySheet(
    BuildContext context, {
    required String title,
    required List<String> options,
    required String? selected,
    required ValueChanged<String?> onSelected,
    bool includeAllOption = false,
  }) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    // Sorted alphabetically so long lists (e.g. instruments) read in a
    // predictable order instead of whatever order they were declared in.
    final sortedOptions = [...options]..sort();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: extension?.cardColor ?? theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        var localSelection = selected;
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final sheetTheme = Theme.of(sheetContext);

            // Toggle: tapping the already-selected chip clears the filter
            // instead of re-selecting it — `option` here is a fixed chip
            // value, never null, so only the "already selected" case needs
            // to fall back to null.
            void select(String? option) {
              final next = localSelection == option ? null : option;
              onSelected(next); // lógica existente — callback global intacto
              setModalState(() => localSelection = next);
            }

            // `DraggableScrollableSheet` (same pattern as the legal-terms
            // sheet in LoginScreen) instead of a plain fixed-height Column —
            // with enough options the chips no longer overflow past the
            // screen edge with no way to reach them.
            return DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: sheetTheme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (includeAllOption)
                              _FilterChip(
                                label: 'Todos',
                                selected: localSelection == null,
                                onTap: () => select(null),
                              ),
                            for (final option in sortedOptions)
                              _FilterChip(
                                label: option,
                                selected: localSelection == option,
                                onTap: () => select(option),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;
    final subtleFill =
        extension?.inputFill ??
        (isDark ? const Color(0xFF171717) : const Color(0xFFF1F5F9));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            // 🔒 FASE 3: Intercepta y limpia la consulta antes de enviarla
            onChanged: (rawQuery) {
              final cleanQuery = InputSanitizer.sanitizeSearchQuery(rawQuery);
              onSearchChanged(cleanQuery);
            },
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              filled: true,
              fillColor: subtleFill,
              hintText: 'Buscar músico, instrumento, ciudad...',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Horizontally scrollable instead of 4 `Expanded` columns — with
          // Ciudad added, equal-width columns were squeezing every emoji +
          // label into an unreadably narrow chip. A fixed width per chip
          // plus a side-scroll keeps each one legible on any screen size.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: _CategoryDropdownField(
                    emoji: '🎵',
                    label: 'Género',
                    onTap: () => _openCategorySheet(
                      context,
                      title: 'Género',
                      options: MusicGenres.all,
                      selected: selectedGenre,
                      onSelected: onGenreSelected,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 140,
                  child: _CategoryDropdownField(
                    emoji: '🎸',
                    label: 'Instrumento',
                    onTap: () => _openCategorySheet(
                      context,
                      title: 'Instrumento',
                      options: VallenatoInstruments.all,
                      selected: selectedInstrument,
                      onSelected: onInstrumentSelected,
                      includeAllOption: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 140,
                  child: _CategoryDropdownField(
                    emoji: '💼',
                    label: 'Servicios',
                    onTap: () => _openCategorySheet(
                      context,
                      title: 'Servicios',
                      options: MusicianServices.all,
                      selected: selectedService,
                      onSelected: onServiceSelected,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 140,
                  child: _CategoryDropdownField(
                    emoji: '📍',
                    label: selectedCityFilter ?? 'Ciudad',
                    onClear: selectedCityFilter != null
                        ? () => onCityFilterSelected(null)
                        : null,
                    onTap: () async {
                      final selected = await showCityPickerSheet(
                        context,
                        title: 'Buscar por ciudad',
                      );
                      if (selected != null) onCityFilterSelected(selected);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _SwitchOption(
                    icon: Icons.people_alt_rounded,
                    label: 'Músicos libres',
                    value: onlyFree,
                    onChanged: onOnlyFreeChanged,
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 10,
                  endIndent: 10,
                  color:
                      extension?.textSecondary.withValues(alpha: 0.15) ??
                      Colors.grey.withValues(alpha: 0.15),
                ),
                Expanded(
                  child: _SwitchOption(
                    icon: Icons.location_on_rounded,
                    label: 'De mi ciudad',
                    value: !searchNationwide,
                    onChanged: (onlyMyCity) =>
                        onNationwideChanged(!onlyMyCity),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const Text('📍 ', style: TextStyle(fontSize: 13)),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: extension?.textSecondary,
                      ),
                      children: selectedCityFilter != null
                          ? [
                              const TextSpan(text: 'Mostrando músicos en '),
                              TextSpan(
                                text: selectedCityFilter,
                                style: const TextStyle(
                                  color: AppColors.whatsAppIndigo,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const TextSpan(text: ' y alrededores.'),
                            ]
                          : searchNationwide
                          ? const [
                              TextSpan(text: 'Mostrando músicos de toda'),
                              TextSpan(
                                text: ' Colombia',
                                style: TextStyle(
                                  color: Color(0xFF38BDF8),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(text: '.'),
                            ]
                          : [
                              const TextSpan(
                                text: 'Mostrando músicos cerca de ',
                              ),
                              TextSpan(
                                text: (homeCity != null && homeCity!.isNotEmpty)
                                    ? homeCity!
                                    : 'tu ciudad',
                                style: const TextStyle(
                                  color: AppColors.whatsAppIndigo,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const TextSpan(text: '.'),
                            ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryDropdownField extends StatelessWidget {
  const _CategoryDropdownField({
    required this.emoji,
    required this.label,
    required this.onTap,
    this.onClear,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

  /// When non-null, an active selection is showing (e.g. a picked city) —
  /// renders a small "×" instead of the chevron so it can be cleared
  /// without reopening the picker just to pick nothing.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;
    final fill =
        extension?.inputFill ??
        (isDark ? const Color(0xFF171717) : const Color(0xFFF1F5F9));
    final border =
        extension?.textSecondary.withValues(alpha: 0.18) ??
        Colors.grey.withValues(alpha: 0.18);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                '$emoji $label',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: extension?.textSecondary,
                ),
              ),
            ),
            if (onClear != null)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: extension?.textSecondary,
                ),
              )
            else
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: extension?.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

class _SwitchOption extends StatelessWidget {
  const _SwitchOption({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: extension?.textSecondary),
          const SizedBox(width: 4),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: extension?.textSecondary,
                ),
              ),
            ),
          ),
          Transform.scale(
            scale: 0.75,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.accent,
            ),
          ),
        ],
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