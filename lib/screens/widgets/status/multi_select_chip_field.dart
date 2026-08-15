import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Multi-selection chip field shared by every "pick one or more" section in
/// "Mi Estado" (instruments, genres, services). Wrapping the [FilterChip]s in
/// a [Wrap] instead of a fixed-width [Row]/[DropdownButtonFormField] is what
/// lets long option lists flow onto new lines instead of overflowing the
/// screen — the fix for the "Right overflowed by 31 pixels" error the old
/// single-line selectors caused.
class MultiSelectChipField extends StatelessWidget {
  const MultiSelectChipField({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  void _toggle(String option) {
    final next = List<String>.from(selected);
    if (next.contains(option)) {
      next.remove(option);
    } else {
      next.add(option);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          FilterChip(
            label: Text(option),
            selected: selected.contains(option),
            onSelected: (_) => _toggle(option),
            showCheckmark: false,
            backgroundColor: extension?.inputFill,
            selectedColor: AppColors.accent,
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: selected.contains(option)
                  ? Colors.black
                  : extension?.textSecondary,
            ),
            side: BorderSide(
              color: selected.contains(option)
                  ? Colors.transparent
                  : (extension?.textSecondary.withValues(alpha: 0.25) ??
                        Colors.grey),
            ),
          ),
      ],
    );
  }
}
