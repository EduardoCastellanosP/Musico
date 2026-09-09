import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme/app_theme.dart';

/// Optional public social links — shown as conditional icons on
/// [ProfileHeader] when set. Format validation (must be a well-formed
/// http(s) URL) happens in `StatusScreen._validate`; this card is purely
/// presentational, matching [ProfileInfoCard]'s split of concerns.
class SocialLinksCard extends StatelessWidget {
  const SocialLinksCard({
    super.key,
    required this.facebookController,
    required this.instagramController,
    required this.tiktokController,
  });

  final TextEditingController facebookController;
  final TextEditingController instagramController;
  final TextEditingController tiktokController;

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
            'Redes sociales',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Opcional — aparecen como íconos en tu perfil público.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _SocialField(
            controller: facebookController,
            icon: FontAwesomeIcons.facebook,
            iconColor: const Color(0xFF1877F2),
            hintText: 'https://facebook.com/tu-pagina',
          ),
          const SizedBox(height: 14),
          _SocialField(
            controller: instagramController,
            icon: FontAwesomeIcons.instagram,
            iconColor: const Color(0xFFE1306C),
            hintText: 'https://instagram.com/tu-usuario',
          ),
          const SizedBox(height: 14),
          _SocialField(
            controller: tiktokController,
            icon: FontAwesomeIcons.tiktok,
            iconColor: isDark ? Colors.white : Colors.black,
            hintText: 'https://tiktok.com/@tu-usuario',
          ),
        ],
      ),
    );
  }
}

class _SocialField extends StatelessWidget {
  const _SocialField({
    required this.controller,
    required this.icon,
    required this.iconColor,
    required this.hintText,
  });

  final TextEditingController controller;
  final IconData icon;
  final Color iconColor;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.url,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(14),
          child: FaIcon(icon, size: 18, color: iconColor),
        ),
      ),
    );
  }
}
