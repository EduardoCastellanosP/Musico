import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../theme_toggle_button.dart';

/// Top-of-dashboard greeting: musician's real name from their Supabase
/// profile, a live count of who's free right now, and quick access to
/// theme toggle + "Mi Estado".
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.greetingName,
    required this.availableCount,
    required this.onSettingsTap,
  });

  final String? greetingName;
  final int availableCount;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greetingName == null ? 'Hola 👋' : 'Hola, $greetingName 👋',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$availableCount músico${availableCount == 1 ? '' : 's'} '
                      'disponible${availableCount == 1 ? '' : 's'} ahora',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: extension?.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const ThemeToggleButton(),
          const SizedBox(width: 10),
          Material(
            color: extension?.cardColor ?? theme.cardColor,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onSettingsTap,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.settings_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
