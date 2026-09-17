import 'package:flutter/material.dart';

import '../../client_profile_screen.dart';

const _kSurface = Color(0xFF17171D);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

/// "The Booking Gate" prompt — shown when a client taps "Reservar"/"Cotizar"
/// on a service but [isProfileCompleteForBooking] says their own profile
/// isn't ready yet (missing name, photo, or WhatsApp). Mirrors
/// `complete_profile_prompt.dart`'s exact scale+fade entrance, styled for
/// the Tarima's dark palette instead of the Backstage theme.
Future<void> showBookingGatePrompt(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Completa tu perfil',
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => const _BookingGateDialog(),
    transitionBuilder: (context, animation, _, child) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return Opacity(
        opacity: animation.value.clamp(0, 1),
        child: Transform.scale(scale: 0.85 + 0.15 * curve.value, child: child),
      );
    },
  );
}

class _BookingGateDialog extends StatelessWidget {
  const _BookingGateDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kSurface,
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
                color: _kAccent.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: _kAccent.withValues(alpha: 0.25),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.event_available_rounded, color: _kAccent, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Completa tu perfil para reservar',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Los artistas necesitan tu nombre, tu foto y tu WhatsApp para '
              'confirmar los detalles de tu evento antes de aceptar la reserva.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kTextSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ClientProfileScreen()),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              child: const Text('Ahora no', style: TextStyle(color: _kTextSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
