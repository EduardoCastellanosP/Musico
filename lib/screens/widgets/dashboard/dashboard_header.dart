import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_notifier.dart';

const List<String> _weekdayNames = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

const List<String> _monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// "Viernes, 15 de agosto" — purely cosmetic date label for the header, not
/// tied to any repository call or persisted state.
String _friendlyToday() {
  final now = DateTime.now();
  final weekday = _weekdayNames[now.weekday - 1];
  final capitalizedWeekday = weekday[0].toUpperCase() + weekday.substring(1);
  return '$capitalizedWeekday, ${now.day} de ${_monthNames[now.month - 1]}';
}

/// Top-of-dashboard hero: gradient banner with today's date, the musician's
/// real name from their Supabase profile, a live count of who's free right
/// now, the "VALLENATOCONNECT" brand mark, and quick access to theme
/// toggle + "Mi Estado". Visual only — every value below is still exactly
/// what [DashboardScreen] already computes and passes in.
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
    final isDark = theme.brightness == Brightness.dark;
    // The hero banner stays a saturated, dark-ish gradient in both themes
    // (navy/violet in dark mode, primary/sky blue in light mode) so white
    // text reads cleanly on top of either — this is what keeps the header
    // feeling equally premium in Light Mode instead of just inverting to a
    // pale background that would wash out the greeting.
    final gradientColors = isDark
        ? AppColors.dashboardHeaderGradientDark
        : AppColors.dashboardHeaderGradientLight;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: HeaderWavesPainter(isDark: isDark)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: _HeaderContent(
                greetingName: greetingName,
                availableCount: availableCount,
                onSettingsTap: onSettingsTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything the header shows on top of [HeaderWavesPainter] — split out
/// purely so [DashboardHeader.build] stays focused on the Stack/gradient
/// shell around it.
class _HeaderContent extends StatelessWidget {
  const _HeaderContent({
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _friendlyToday(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Same `themeModeNotifier`/`toggleThemeMode` as the shared
            // ThemeToggleButton (used as-is on the login screen) — only
            // restyled here as a translucent circle so it reads correctly
            // against the gradient instead of the solid card-color chip
            // that widget renders on a plain background.
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModeNotifier,
              builder: (context, mode, _) => _CircleIconButton(
                icon: mode == ThemeMode.dark
                    ? Icons.wb_sunny_rounded
                    : Icons.nightlight_round,
                onTap: toggleThemeMode, // lógica existente
              ),
            ),
            const SizedBox(width: 10),
            _CircleIconButton(
              icon: Icons.settings_rounded,
              onTap: onSettingsTap, // lógica existente
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          greetingName == null ? 'Hola 👋' : '$greetingName',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF22C55E),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$availableCount Músico${availableCount == 1 ? '' : 's'} '
              'disponible${availableCount == 1 ? '' : 's'} ahora',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'VALLENATOCONNECT',
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.65),
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 2,
          width: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              colors: [Color(0xFFEC4899), Color(0xFF60A5FA)],
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: CircleBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// Draws 3 overlapping soft curves across the header's gradient — the
/// abstract "waves/bubbles" texture premium apps use to break up a flat
/// gradient, without shipping an image asset.
class HeaderWavesPainter extends CustomPainter {
  const HeaderWavesPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final waveColor = isDark ? const Color(0xFF818CF8) : Colors.white;

    void drawWave({
      required double baseHeightFactor,
      required double amplitude,
      required double opacity,
    }) {
      final baseHeight = size.height * baseHeightFactor;
      final path = Path()
        ..moveTo(0, baseHeight)
        ..quadraticBezierTo(
          size.width * 0.25,
          baseHeight - amplitude,
          size.width * 0.5,
          baseHeight,
        )
        ..quadraticBezierTo(
          size.width * 0.75,
          baseHeight + amplitude,
          size.width,
          baseHeight,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();

      canvas.drawPath(
        path,
        Paint()..color = waveColor.withValues(alpha: opacity),
      );
    }

    drawWave(baseHeightFactor: 0.60, amplitude: 20, opacity: 0.08);
    drawWave(baseHeightFactor: 0.74, amplitude: 16, opacity: 0.12);
    drawWave(baseHeightFactor: 0.88, amplitude: 12, opacity: 0.18);
  }

  @override
  bool shouldRepaint(covariant HeaderWavesPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
