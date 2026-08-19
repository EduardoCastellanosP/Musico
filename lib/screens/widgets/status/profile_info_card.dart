import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../phone_input_field.dart';
import 'city_picker_sheet.dart';

/// Editable public identity fields — name, city and WhatsApp phone — the
/// same data every other musician sees on this musician's dashboard card.
/// Instruments, genres and services live in their own cards since which of
/// those show up depends on the services the musician selects.
class ProfileInfoCard extends StatelessWidget {
  const ProfileInfoCard({
    super.key,
    required this.fullNameController,
    required this.cityController,
    required this.phoneController,
  });

  final TextEditingController fullNameController;
  final TextEditingController cityController;
  final TextEditingController phoneController;

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
          _FieldLabel('Ciudad'),
          const SizedBox(height: 6),
          TextField(
            controller: cityController,
            readOnly: true,
            // Picking from `CityPickerSheet` instead of free-typing is what
            // keeps `city` consistent enough for `CityZones`/"Cercanías"
            // matching to actually work — see CityZones' doc comment.
            onTap: () async {
              final selected = await showCityPickerSheet(
                context,
                title: 'Elige tu ciudad principal',
              );
              if (selected != null) cityController.text = selected;
            },
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'Ej: Valledupar',
              prefixIcon: Icon(Icons.location_on_outlined),
              suffixIcon: Icon(Icons.expand_more_rounded),
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
