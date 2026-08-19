import 'package:flutter/material.dart';

import '../../../core/constants/genres.dart';
import '../../../core/constants/instruments.dart';
import '../../../core/constants/services.dart';
import '../../../core/theme/app_theme.dart';

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
  /// "Solo mi ciudad" switch and the caption below it — the actual
  /// filtering happens server-side in `MusicianRepository.fetchMusicians`.
  final String? homeCity;

  /// Opens the bottom sheet for one category (Género/Instrumento/Servicios).
  ///
  /// [selected]/[onSelected] are exactly the props this widget was given —
  /// tapping a chip still calls that same global callback. The sheet also
  /// keeps a `localSelection` copy purely so it can redraw itself the
  /// instant a chip is tapped: [SearchFilterBar] is a [StatelessWidget], so
  /// its `selected` field is frozen to whatever it was when the sheet was
  /// opened and only changes once the parent rebuilds a *new*
  /// `SearchFilterBar` — which normally wouldn't happen until this sheet is
  /// closed and reopened. The [StatefulBuilder] + local variable make the
  /// sheet reactive in the meantime without touching any app state.
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

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: extension?.cardColor ?? theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        var localSelection = selected;
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final sheetTheme = Theme.of(sheetContext);

            void select(String? option) {
              onSelected(option); // lógica existente — callback global intacto
              setModalState(() => localSelection = option);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                        for (final option in options)
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
            onChanged: onSearchChanged,
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
          Row(
            children: [
              Expanded(
                child: _CategoryDropdownField(
                  emoji: '🎵',
                  label: 'Género',
                  onTap: () => _openCategorySheet(
                    context,
                    title: 'Género',
                    options: MusicGenres.all,
                    selected: selectedGenre,
                    onSelected: onGenreSelected, // lógica existente
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CategoryDropdownField(
                  emoji: '🎸',
                  label: 'Instrumento',
                  onTap: () => _openCategorySheet(
                    context,
                    title: 'Instrumento',
                    options: VallenatoInstruments.all,
                    selected: selectedInstrument,
                    onSelected: onInstrumentSelected, // lógica existente
                    includeAllOption: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CategoryDropdownField(
                  emoji: '💼',
                  label: 'Servicios',
                  onTap: () => _openCategorySheet(
                    context,
                    title: 'Servicios',
                    options: MusicianServices.all,
                    selected: selectedService,
                    onSelected: onServiceSelected, // lógica existente
                  ),
                ),
              ),
            ],
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
                    onChanged: onOnlyFreeChanged, // lógica existente
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
                    // `searchNationwide` is the underlying state; this
                    // switch just reads/writes it inverted so "ON" means
                    // "cerca de mí" (the label the design calls for)
                    // instead of "todo el país" — same callback, same
                    // state, only the boolean is flipped at the UI edge.
                    value: !searchNationwide,
                    onChanged: (onlyMyCity) =>
                        onNationwideChanged(!onlyMyCity), // lógica existente
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
                      children: searchNationwide
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

/// One of the three pill-shaped "dropdown" buttons (Género/Instrumento/
/// Servicios) that open a bottom sheet with the real picker. Always renders
/// with the same subtle, static fill/border — no highlight color based on
/// whether a selection is active.
class _CategoryDropdownField extends StatelessWidget {
  const _CategoryDropdownField({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

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

/// Half of the split switch row: icon, label and [Switch] all on one line
/// (`Row: [Icono, texto, Spacer(), Switch]`), driven by the exact
/// [value]/[onChanged] pair passed in from [SearchFilterBar].
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
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
      ), // Margen ajustado para ganar espacio
      child: Row(
        children: [
          Icon(icon, size: 14, color: extension?.textSecondary),
          const SizedBox(width: 4),
          Expanded(
            child: FittedBox(
              fit: BoxFit
                  .scaleDown, // <--- La clave: escala el texto si es muy largo para que NUNCA se corte
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
            scale: 0.75, // Switch un poco más compacto horizontalmente
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
