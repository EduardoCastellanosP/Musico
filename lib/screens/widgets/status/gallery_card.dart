import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/musician_photo.dart';

/// Portfolio of live-performance photos: a horizontally scrolling strip of
/// thumbnails plus an "add" tile, backed by the `musician_photos` table and
/// the `musician-photos` Storage bucket.
class GalleryCard extends StatelessWidget {
  const GalleryCard({
    super.key,
    required this.photos,
    required this.uploading,
    required this.onAddPhoto,
    required this.onDeletePhoto,
  });

  final List<MusicianPhoto> photos;
  final bool uploading;
  final VoidCallback onAddPhoto;
  final ValueChanged<MusicianPhoto> onDeletePhoto;

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
            'Galería de presentaciones',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Muestra tu trabajo en vivo a los organizadores.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _AddPhotoTile(uploading: uploading, onTap: onAddPhoto),
                for (final photo in photos)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: _PhotoThumbnail(
                      photo: photo,
                      onDelete: () => onDeletePhoto(photo),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.uploading, required this.onTap});

  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: uploading ? null : onTap,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: extension?.inputFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.4),
            style: BorderStyle.solid,
          ),
        ),
        child: uploading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.accent,
                  ),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.add_a_photo_outlined,
                    color: AppColors.accent,
                    size: 26,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Agregar',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: extension?.textSecondary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({required this.photo, required this.onDelete});

  final MusicianPhoto photo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              photo.imageUrl,
              width: 96,
              height: 96,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
