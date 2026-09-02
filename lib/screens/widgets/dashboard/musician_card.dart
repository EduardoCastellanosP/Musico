import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/musician.dart';

class MusicianCard extends StatelessWidget {
  const MusicianCard({
    super.key,
    required this.musician,
    required this.onWhatsAppTap,
    required this.onCallTap,
    required this.onTap,
  });

  final Musician musician;
  final VoidCallback onWhatsAppTap;
  final VoidCallback onCallTap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1A1F36)
              : (extension?.cardColor ?? theme.cardColor),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark ? null : AppColors.lightCardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 32,
                    child: _MusicianImageFrame(musician: musician),
                  ),
                  Expanded(
                    flex: 68,
                    child: _MusicianCardContent(
                      musician: musician,
                      onWhatsAppTap: onWhatsAppTap,
                      onCallTap: onCallTap,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Caps how tall the photo side of the card can force the whole [Row] to
/// grow. `IntrinsicHeight` (in [MusicianCard.build]) sizes the row by
/// asking each child its *intrinsic* height for the available width — an
/// unconstrained [Image] answers with whatever height its natural aspect
/// ratio implies, so a musician uploading a very tall/narrow photo used to
/// blow up the whole card. Wrapping it in a fixed-height [SizedBox] caps
/// that answer; `CrossAxisAlignment.stretch` on the Row still stretches the
/// image to the row's *actual* final height (driven by the text side)
/// afterwards, so normal-sized photos are unaffected.
class _MusicianImageFrame extends StatelessWidget {
  const _MusicianImageFrame({required this.musician});

  final Musician musician;

  static const double _maxIntrinsicHeight = 118;

  @override
  Widget build(BuildContext context) {
    final image = _MusicianImage(musician: musician);
    return SizedBox(
      height: _maxIntrinsicHeight,
      child: musician.recentlyUploaded
          ? _StoryRing(child: image)
          : image,
    );
  }
}

/// WhatsApp/Instagram-style gradient ring signaling the musician uploaded a
/// photo or video in the last 48h ([Musician.recentlyUploaded]) — a thin
/// gradient border inset from the card's own edge so it reads as a "story"
/// frame rather than just a colored outline.
class _StoryRing extends StatelessWidget {
  const _StoryRing({required this.child});

  final Widget child;

  static const _ringGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF8B5CF6)],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: _ringGradient),
      padding: const EdgeInsets.all(3),
      child: ClipRect(child: child),
    );
  }
}

class _MusicianImage extends StatelessWidget {
  const _MusicianImage({required this.musician});
  final Musician musician;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = musician.avatarUrl;
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return _InitialsPlaceholder(musician: musician);
    }
    return Image.network(
      avatarUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          _InitialsPlaceholder(musician: musician),
    );
  }
}

class _InitialsPlaceholder extends StatelessWidget {
  const _InitialsPlaceholder({required this.musician});
  final Musician musician;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: AppColors.accent.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        musician.initials,
        style: theme.textTheme.headlineSmall?.copyWith(
          color: AppColors.accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MusicianCardContent extends StatelessWidget {
  const _MusicianCardContent({
    required this.musician,
    required this.onWhatsAppTap,
    required this.onCallTap,
  });

  final Musician musician;
  final VoidCallback onWhatsAppTap;
  final VoidCallback onCallTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;

    // Category emoji so the card reads at a glance whether this is a
    // performer (instruments) or a technical provider (sound gear, venues).
    final categoryEmoji = musician.offersMusicianService
        ? ' '
        : musician.offersTechnicalService
        ? ' '
        : '';
    final serviceLine = musician.instruments.isNotEmpty
        ? '$categoryEmoji${musician.instrumentsSummary}'
        : '$categoryEmoji${musician.services.join(' · ')}';

    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: extension?.textSecondary,
      fontSize: 11.5,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  musician.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusDot(isFree: musician.isFree),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _RatingStars(rating: musician.rating),
              if (musician.city.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text('•', style: subtitleStyle),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    musician.city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
                ),
              ],
            ],
          ),
          if (musician.genres.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              musician.genres.join('   —   '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle,
            ),
          ],
          if (serviceLine.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            _ServiceChip(label: serviceLine, isDark: isDark),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  iconWidget: SvgPicture.asset(
                    'assets/images/logowpp.svg',
                    width: 20,
                    height: 20,
                  ),
                  label: 'Wpp',
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  onTap: musician.hasPhone ? onWhatsAppTap : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.call_rounded,
                  label: 'Llamar',
                  backgroundColor: AppColors.whatsAppIndigo,
                  foregroundColor: Colors.white,
                  onTap: musician.hasPhone ? onCallTap : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Houses the instrument/service line as the card's visual core — a
/// rounded, accent-tinted chip instead of plain text, so what the musician
/// actually offers is what draws the eye.
class _ServiceChip extends StatelessWidget {
  const _ServiceChip({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.accent,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Small pulsing dot standing in for the old "Disponible ahora"/"Ocupado"
/// text — emerald while free, crimson while busy, no label needed.
///
/// The [AnimationController] only drives this widget's own `builder`
/// closure, and [RepaintBoundary] scopes the resulting per-frame repaint to
/// just this dot, so a list full of these pulsing independently doesn't
/// cost scroll FPS.
class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.isFree});

  final bool isFree;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  static const _free = Color(0xFF10B981); // verde
  static const _busy = Color(0xFFDC2626); // rojo

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isFree ? _free : _busy;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final glow = 0.4 + _controller.value * 0.5;
          return Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: glow),
                  blurRadius: 5 + _controller.value * 3,
                  spreadRadius: 1,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Compact fixed 5-star rating, gold fill proportional to
/// [Musician.rating] — half-star granularity.
class _RatingStars extends StatelessWidget {
  const _RatingStars({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final threshold = index + 1;
        final IconData icon;
        if (rating >= threshold) {
          icon = Icons.star_rounded;
        } else if (rating >= threshold - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_border_rounded;
        }
        return Icon(icon, size: 13, color: Colors.amber);
      }),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  }) : assert(icon != null || iconWidget != null, 'Provide either icon or iconWidget');

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final Color backgroundColor;
  final Color? foregroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: iconWidget ?? Icon(icon, size: 16),
        label: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
