import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_notifier.dart';

/// Top-of-screen control that flips [themeModeNotifier].
///
/// Shows the icon of the mode a tap would *land on* to hint at the switch:
/// a moon while in light mode (tap to go dark), a sun while in dark mode
/// (tap to go light).
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        final extension = Theme.of(context).extension<AppThemeExtension>();
        return Material(
          color: extension?.cardColor ?? Theme.of(context).cardColor,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: toggleThemeMode,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                color: AppColors.accent,
                size: 20,
              ),
            ),
          ),
        );
      },
    );
  }
}
