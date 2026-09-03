import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../status_screen.dart';

/// Friendly modal shown when a signed-in user whose own profile isn't
/// complete yet ([Musician.hasCompleteProfile]) taps WhatsApp/Llamar on
/// someone else's card. Browsing the whole directory never requires a
/// finished profile — only *contacting* talent does — so this is the
/// explanation shown instead of the tap just silently doing nothing, with
/// a direct shortcut into "Mi Estado".
Future<void> showCompleteProfilePrompt(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Completa tu perfil',
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => const _CompleteProfileDialog(),
    transitionBuilder: (context, animation, _, child) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return Opacity(
        opacity: animation.value.clamp(0, 1),
        child: Transform.scale(scale: 0.85 + 0.15 * curve.value, child: child),
      );
    },
  );
}

class _CompleteProfileDialog extends StatelessWidget {
  const _CompleteProfileDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return Dialog(
      backgroundColor: extension?.cardColor ?? theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.25),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.person_search_rounded,
                color: AppColors.accent,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Completa tu perfil para contactar',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Para escribir o llamar a otros músicos primero necesitas '
              'terminar tu propio perfil: ubicación, WhatsApp, un servicio '
              'y al menos 1 foto y 1 video.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: extension?.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StatusScreen()),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.profileAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Completar mi perfil',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Ahora no'),
            ),
          ],
        ),
      ),
    );
  }
}
