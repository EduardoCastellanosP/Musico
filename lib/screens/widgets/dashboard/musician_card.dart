import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/constants/whatsapp.dart';
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

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1F36)
            : (extension?.cardColor ?? theme.cardColor),
        borderRadius: BorderRadius.circular(20),
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
                Expanded(flex: 38, child: _MusicianImage(musician: musician)),
                Expanded(
                  flex: 62,
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

    final chipBackground = isDark
        ? AppColors.infoChipBackgroundDark
        : AppColors.infoChipBackgroundLight;
    final chipForeground = isDark
        ? AppColors.infoChipForegroundDark
        : AppColors.infoChipForegroundLight;

    final subtitle = musician.instruments.isNotEmpty
        ? musician.instrumentsSummary
        : musician.services.join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: extension?.textSecondary,
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: extension?.textSecondary,
              ),
            ),
          ],
          if (musician.genres.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final genre in musician.genres)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: chipBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      genre,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: chipForeground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (musician.city.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on_rounded, size: 13, color: extension?.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    musician.city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: extension?.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: musician.isFree ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  musician.availabilityLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: musician.isFree ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  iconWidget: SvgPicture.asset(
                    'assets/images/logowpp.svg',
                    width: 20,
                    height: 20,
                    // colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
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