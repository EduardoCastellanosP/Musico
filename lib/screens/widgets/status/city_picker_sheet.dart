import 'package:flutter/material.dart';

import '../../../core/constants/colombia_cities.dart';
import '../../../core/theme/app_theme.dart';

/// Opens the searchable municipio picker used by [ProfileInfoCard]'s base
/// city field and [CoverageCitiesCard]'s "add municipio" button. Resolves to
/// the picked city name, or `null` if the sheet was dismissed without a
/// selection.
Future<String?> showCityPickerSheet(
  BuildContext context, {
  String title = 'Elige tu municipio',
}) {
  final theme = Theme.of(context);
  final extension = theme.extension<AppThemeExtension>();

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: extension?.cardColor ?? theme.cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _CityPickerSheet(title: title),
  );
}

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({required this.title});

  final String title;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  static final List<MapEntry<String, String>> _allEntries = [
    for (final department in ColombiaCities.byDepartment.entries)
      for (final city in department.value) MapEntry(city, department.key),
  ];

  final TextEditingController _controller = TextEditingController();
  List<MapEntry<String, String>> _results = _allEntries;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    final trimmed = query.trim().toLowerCase();
    setState(() {
      _results = trimmed.isEmpty
          ? _allEntries
          : _allEntries
                .where((entry) => entry.key.toLowerCase().contains(trimmed))
                .toList();
    });
  }

  bool _hasExactMatch(String query) => _allEntries.any(
    (entry) => entry.key.toLowerCase() == query.trim().toLowerCase(),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final query = _controller.text.trim();
    final showFreeTextOption = query.isNotEmpty && !_hasExactMatch(query);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
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
              textCapitalization: TextCapitalization.words,
              onChanged: _onQueryChanged,
              style: theme.textTheme.bodyLarge,
              decoration: const InputDecoration(
                hintText: 'Busca tu municipio...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 340,
              child: ListView(
                children: [
                  if (showFreeTextOption) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.edit_location_alt_outlined,
                        color: AppColors.profileAccent,
                      ),
                      title: Text('Usar "$query"'),
                      subtitle: Text(
                        'No está en la lista, pero puedes usarlo tal cual.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: extension?.textSecondary,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, query),
                    ),
                    const Divider(height: 20),
                  ],
                  if (_results.isEmpty && !showFreeTextOption)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No encontramos municipios con ese nombre.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: extension?.textSecondary,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final entry in _results)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.key),
                        subtitle: Text(
                          entry.value,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: extension?.textSecondary,
                          ),
                        ),
                        onTap: () => Navigator.pop(context, entry.key),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
