import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/musician.dart';

/// Profile header: a background image that fades into
/// [ThemeData.scaffoldBackgroundColor], an avatar overlapping that seam,
/// and the name/genre/role/rating/availability block underneath. Used by
/// [MusicianDetailScreen] as the first sliver of its [CustomScrollView].
///
/// [backgroundImageUrl] is a plain prop rather than something this widget
/// derives itself — the caller decides what photo represents the header
/// (currently the musician's first uploaded portfolio photo, or their own
/// `cover_url` on "Mi Estado"), keeping this widget a dumb renderer.
/// [onEditCover]/[onEditAvatar] are null for the read-only case (viewing
/// another musician) — [MusicianDetailScreen] never passes them;
/// [StatusScreen] does, since that's the only screen where editing your
/// own profile makes sense.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.musician,
    this.backgroundImageUrl,
    this.onEditCover,
    this.uploadingCover = false,
    this.onEditAvatar,
    this.uploadingAvatar = false,
  });

  final Musician musician;
  final String? backgroundImageUrl;
  final VoidCallback? onEditCover;
  final bool uploadingCover;
  final VoidCallback? onEditAvatar;
  final bool uploadingAvatar;

  static const double _headerHeight = 200;
  static const double _avatarRadius = 48;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _headerHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              _BackgroundImage(
                url: backgroundImageUrl,
                height: _headerHeight,
                onEdit: uploadingCover ? null : onEditCover,
                uploading: uploadingCover,
              ),
              // Centered on the image/background seam (half above, half
              // below) — `Clip.none` on the Stack is what lets this paint
              // past its own bottom edge instead of being cut off.
              Positioned(
                bottom: -_avatarRadius,
                child: _AvatarWithStatusDot(
                  musician: musician,
                  radius: _avatarRadius,
                  onTap: uploadingAvatar ? null : onEditAvatar,
                  uploading: uploadingAvatar,
                ),
              ),
            ],
          ),
        ),
        // Reserves room for the bottom half of the overlapping avatar
        // before the text content starts.
        const SizedBox(height: _avatarRadius + 14),
        _ProfileInfo(musician: musician),
      ],
    );
  }
}

/// The image itself plus the fade-to-background gradient — falls back to a
/// plain gradient panel (no broken-image icon) when [url] is null, since a
/// musician with no uploaded photos yet is a normal, expected state.
class _BackgroundImage extends StatelessWidget {
  const _BackgroundImage({
    required this.url,
    required this.height,
    required this.onEdit,
    required this.uploading,
  });

  final String? url;
  final double height;
  final VoidCallback? onEdit;

  /// Keeps the edit button's slot visible (as a spinner) even though
  /// [onEdit] is null while an upload is in flight — [ProfileHeader]
  /// passes `null` for [onEdit] precisely to disable the tap during that
  /// window, so this is the only way to tell "editable but busy" apart
  /// from "not editable at all" (e.g. viewing someone else's profile).
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = theme.scaffoldBackgroundColor;
    final hasImage = url != null && url!.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _placeholderGradient(theme),
            )
          else
            _placeholderGradient(theme),
          // Transparent -> scaffold background, so the image dissolves
          // into the rest of the scrollable body instead of ending on a
          // hard edge.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, backgroundColor],
              ),
            ),
          ),
          if (onEdit != null || uploading)
            Positioned(
              right: 12,
              top: 12,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onEdit,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholderGradient(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? AppColors.dashboardHeaderGradientDark
              : AppColors.dashboardHeaderGradientLight,
        ),
      ),
    );
  }
}

class _AvatarWithStatusDot extends StatelessWidget {
  const _AvatarWithStatusDot({
    required this.musician,
    required this.radius,
    this.onTap,
    this.uploading = false,
  });

  final Musician musician;
  final double radius;
  final VoidCallback? onTap;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = musician.avatarUrl;
    final diameter = radius * 2;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: uploading ? null : onTap,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.scaffoldBackgroundColor,
                border: Border.all(color: AppColors.accent, width: 3),
              ),
              child: CircleAvatar(
                radius: radius - 3,
                backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? NetworkImage(avatarUrl)
                    : null,
                child: uploading
                    ? const CircularProgressIndicator(color: AppColors.accent)
                    : (avatarUrl == null || avatarUrl.isEmpty)
                    ? Text(
                        musician.initials,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          if (onTap != null && !uploading)
            Positioned(
              right: 0,
              bottom: 18,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: musician.isFree ? Colors.green.shade800 : Colors.red,
                border: Border.all(
                  color: theme.scaffoldBackgroundColor,
                  width: 3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfo extends StatelessWidget {
  const _ProfileInfo({required this.musician});

  final Musician musician;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    // final roleSubtitle = musician.instruments.isNotEmpty
    //     ? musician.instrumentsSummary
    //     : musician.services.join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                musician.fullName,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (musician.genres.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: musician.genres.map((genre) {
                return Chip(
                  label: Text(
                    genre,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],
          // if (roleSubtitle.isNotEmpty) ...[
          //   const SizedBox(height: 4),
          //   Text(
          //     roleSubtitle,
          //     textAlign: TextAlign.center,
          //     style: theme.textTheme.bodyMedium?.copyWith(
          //       color: extension?.textSecondary,
          //     ),
          //   ),
          // ],
          // const SizedBox(height: 10),
          // Wrap(
          //   alignment: WrapAlignment.center,
          //   crossAxisAlignment: WrapCrossAlignment.center,
          //   spacing: 8,
          //   children: [
          //     _RatingStars(rating: musician.rating),
          //     Text(
          //       '${musician.rating.toStringAsFixed(1)} (${musician.reviewsCount})',
          //       style: theme.textTheme.bodyMedium?.copyWith(
          //         color: extension?.textSecondary,
          //       ),
          //     ),
          //     Text(
          //       '· ${musician.experienceYears} años de experiencia',
          //       style: theme.textTheme.bodyMedium?.copyWith(
          //         color: extension?.textSecondary,
          //       ),
          //     ),
          //   ],
          // ),
          const SizedBox(height: 18),
          _AvailabilityBanner(musician: musician),
        ],
      ),
    );
  }
}

class _RatingStars extends StatelessWidget {
  const _RatingStars({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final threshold = index + 1;
        IconData icon;
        if (rating >= threshold) {
          icon = Icons.star_rounded;
        } else if (rating >= threshold - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_border_rounded;
        }
        return Icon(icon, size: 16, color: AppColors.accent);
      }),
    );
  }
}

class _AvailabilityBanner extends StatelessWidget {
  const _AvailabilityBanner({required this.musician});

  final Musician musician;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = musician.isFree ? Colors.green.shade800 : Colors.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time_filled_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              musician.availabilityLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: musician.isFree
                    ? Colors.green.shade800
                    : Colors.red.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}