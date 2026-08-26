import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Multi-selection field for long option lists (instruments, genres,
/// services) — an "Agregar X" trigger (same visual language as
/// [CoverageCitiesCard]'s "Agregar municipio") that opens a searchable
/// bottom sheet, plus the current selection as removable chips underneath.
/// Replaces [MultiSelectChipField] for lists too long to scan as a flat
/// [Wrap] of chips — see [_MultiSelectSearchSheet]'s search field.
class MultiSelectSearchField extends StatelessWidget {
  const MultiSelectSearchField({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.addLabel,
    required this.searchHint,
  });

  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final String addLabel;
  final String searchHint;

  Future<void> _openPicker(BuildContext context) async {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: extension?.cardColor ?? theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _MultiSelectSearchSheet(
        title: addLabel,
        searchHint: searchHint,
        options: options,
        initiallySelected: selected,
      ),
    );
    if (result != null) onChanged(result);
  }

  void _remove(String option) {
    onChanged(selected.where((item) => item != option).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openPicker(context),
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
                const Icon(Icons.search_rounded, color: AppColors.profileAccent),
                const SizedBox(width: 10),
                Text(
                  addLabel,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.profileAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in selected)
                Chip(
                  label: Text(option),
                  onDeleted: () => _remove(option),
                  backgroundColor: AppColors.profileAccent.withValues(alpha: 0.12),
                  deleteIconColor: AppColors.profileAccent,
                  side: BorderSide.none,
                  labelStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.profileAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MultiSelectSearchSheet extends StatefulWidget {
  const _MultiSelectSearchSheet({
    required this.title,
    required this.searchHint,
    required this.options,
    required this.initiallySelected,
  });

  final String title;
  final String searchHint;
  final List<String> options;
  final List<String> initiallySelected;

  @override
  State<_MultiSelectSearchSheet> createState() =>
      _MultiSelectSearchSheetState();
}

class _MultiSelectSearchSheetState extends State<_MultiSelectSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  late final Set<String> _selected = {...widget.initiallySelected};
  late List<String> _results = widget.options;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    final trimmed = query.trim().toLowerCase();
    setState(() {
      _results = trimmed.isEmpty
          ? widget.options
          : widget.options
                .where((option) => option.toLowerCase().contains(trimmed))
                .toList();
    });
  }

  void _toggle(String option) {
    setState(() {
      _selected.contains(option) ? _selected.remove(option) : _selected.add(option);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    // Bounded to the space actually left above the keyboard (rather than a
    // fixed 340 list height) so opening the keyboard to type a search query
    // shrinks the list instead of pushing the sheet's total height past the
    // screen and overflowing.
    final availableHeight =
        MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: availableHeight * 0.85),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onQueryChanged,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        'No encontramos resultados con ese nombre.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: extension?.textSecondary,
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final option in _results)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: AppColors.profileAccent,
                            title: Text(option),
                            value: _selected.contains(option),
                            onChanged: (_) => _toggle(option),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _selected.toList()),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.profileAccent,
                ),
                child: Text(
                  _selected.isEmpty
                      ? 'Listo'
                      : 'Listo (${_selected.length} seleccionado${_selected.length == 1 ? '' : 's'})',
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
