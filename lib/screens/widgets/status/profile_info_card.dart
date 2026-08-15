import 'package:flutter/material.dart';

import '../../../core/constants/genres.dart';
import '../../../core/constants/instruments.dart';
import '../../../core/theme/app_theme.dart';
import '../phone_input_field.dart';

/// Editable public profile fields — name, instrument, genre, city and
/// WhatsApp phone — the same data every other musician sees on this
/// musician's dashboard card.
class ProfileInfoCard extends StatelessWidget {
  const ProfileInfoCard({
    super.key,
    required this.fullNameController,
    required this.cityController,
    required this.phoneController,
    required this.selectedInstrument,
    required this.onInstrumentChanged,
    required this.selectedGenre,
    required this.onGenreChanged,
  });

  final TextEditingController fullNameController;
  final TextEditingController cityController;
  final TextEditingController phoneController;
  final String? selectedInstrument;
  final ValueChanged<String?> onInstrumentChanged;
  final String selectedGenre;
  final ValueChanged<String?> onGenreChanged;

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
            'Información de Perfil',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Así te ven los contratantes en el directorio.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel('Nombre completo'),
          const SizedBox(height: 6),
          TextField(
            controller: fullNameController,
            textCapitalization: TextCapitalization.words,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'Ej: Carlos "El Rey" Martínez',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel('Instrumento'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: selectedInstrument,
            items: [
              for (final instrument in VallenatoInstruments.all)
                DropdownMenuItem(value: instrument, child: Text(instrument)),
            ],
            onChanged: onInstrumentChanged,
            dropdownColor: extension?.cardColor ?? theme.cardColor,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'Selecciona tu instrumento',
              prefixIcon: Icon(Icons.music_note_outlined),
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel('Género musical'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: selectedGenre,
            items: [
              for (final genre in MusicGenres.all)
                DropdownMenuItem(value: genre, child: Text(genre)),
            ],
            onChanged: onGenreChanged,
            dropdownColor: extension?.cardColor ?? theme.cardColor,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'Selecciona tu género musical',
              prefixIcon: Icon(Icons.library_music_outlined),
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel('Ciudad'),
          const SizedBox(height: 6),
          TextField(
            controller: cityController,
            textCapitalization: TextCapitalization.words,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'Ej: Valledupar',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel('Teléfono (WhatsApp)'),
          const SizedBox(height: 6),
          PhoneInputField(controller: phoneController),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: extension?.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
