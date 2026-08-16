import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/musician.dart';

/// The musician's own circular avatar at the top of "Mi Estado", tappable to
/// pick a new photo from the gallery. A small camera badge in the
/// bottom-right corner signals it's editable; a spinner replaces the photo
/// while [uploading] an upload is in flight.
class ProfileAvatarEditor extends StatelessWidget {
  const ProfileAvatarEditor({
    super.key,
    required this.musician,
    required this.uploading,
    required this.onTap,
  });

  final Musician musician;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final avatarUrl = musician.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return Center(
      child: GestureDetector(
        onTap: uploading ? null : onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: AppColors.profileAccent, width: 3),
                ),
              ),
              child: CircleAvatar(
                radius: 48,
                backgroundColor: AppColors.profileAccent.withValues(
                  alpha: 0.15,
                ),
                backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
                child: uploading
                    ? const CircularProgressIndicator(
                        color: AppColors.profileAccent,
                      )
                    : hasAvatar
                    ? null
                    : Text(
                        musician.initials,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: AppColors.profileAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            if (!uploading)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.profileAccent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          extension?.cardColor ?? theme.scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
