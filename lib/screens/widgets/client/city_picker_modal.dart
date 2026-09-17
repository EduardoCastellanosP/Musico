import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/constants/colombia_cities.dart';

const _kBackground = Color(0xFF0D0D12);
const _kSurface = Color(0xFF17171D);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

/// Sentinel [showCityPickerModal] result meaning "don't restrict by city" —
/// `ClientHomeScreen` shows this as "Todas las ciudades" in the header
/// instead of a specific municipio, and skips the city filter entirely.
/// Exists so a sparse/incomplete test dataset (most `provider_services`
/// owners without a `city` set yet) doesn't trap the client on an empty
/// list with no way back.
const String kAnyCity = 'Todas las ciudades';

/// Every entry `ColombiaCities.byDepartment` has, flattened to
/// (municipio, departamento) pairs and alphabetized — the same curated,
/// already-maintained list `CityPickerSheet` uses for "Mi Estado", so a
/// municipio added there shows up here too without touching this file.
final List<MapEntry<String, String>> _kAllCities =
    [
      for (final department in ColombiaCities.byDepartment.entries)
        for (final city in department.value) MapEntry(city, department.key),
    ]..sort((a, b) => a.key.compareTo(b.key));

/// Opens the Tarima's city search/select bottom sheet. Resolves to the
/// picked municipio, [kAnyCity], or `null` if dismissed without a choice.
Future<String?> showCityPickerModal(
  BuildContext context, {
  required String currentCity,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _CityPickerModal(currentCity: currentCity),
  );
}

class _CityPickerModal extends StatefulWidget {
  const _CityPickerModal({required this.currentCity});

  final String currentCity;

  @override
  State<_CityPickerModal> createState() => _CityPickerModalState();
}

class _CityPickerModalState extends State<_CityPickerModal> {
  final _controller = TextEditingController();
  List<MapEntry<String, String>> _results = _kAllCities;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    final trimmed = query.trim().toLowerCase();
    setState(() {
      _results = trimmed.isEmpty
          ? _kAllCities
          : _kAllCities
              .where((entry) => entry.key.toLowerCase().contains(trimmed))
              .toList();
    });
  }

  void _clearQuery() {
    _controller.clear();
    _onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final showAnyCityShortcut = _controller.text.trim().isEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.92,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: _kBackground.withValues(alpha: 0.96),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Selecciona tu ciudad',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _kSurface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextField(
                          controller: _controller,
                          autofocus: false,
                          onChanged: _onQueryChanged,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Buscar ciudad o municipio...',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                            prefixIcon: const Icon(Icons.search, color: _kTextSecondary),
                            suffixIcon: _controller.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, color: _kTextSecondary),
                                    onPressed: _clearQuery,
                                  ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        children: [
                          if (showAnyCityShortcut)
                            _CityTile(
                              icon: Icons.public,
                              title: kAnyCity,
                              subtitle: 'Ver servicios de todo el país',
                              selected: widget.currentCity == kAnyCity,
                              onTap: () => Navigator.of(context).pop(kAnyCity),
                            ),
                          if (_results.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Text(
                                  'No encontramos ciudades con ese nombre.',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                                ),
                              ),
                            )
                          else
                            for (final entry in _results)
                              _CityTile(
                                icon: Icons.location_on_outlined,
                                title: entry.key,
                                subtitle: entry.value,
                                selected: widget.currentCity == entry.key,
                                onTap: () => Navigator.of(context).pop(entry.key),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CityTile extends StatelessWidget {
  const _CityTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _kAccent.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: selected ? _kAccent : _kTextSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: selected ? _kAccent : Colors.white,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _kTextSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, color: _kAccent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
