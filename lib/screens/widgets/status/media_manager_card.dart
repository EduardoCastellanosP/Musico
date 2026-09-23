import 'package:flutter/material.dart';

import '../../../core/constants/media_limits.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/musician_video.dart';
import '../../../models/provider_service.dart';
import '../../in_app_video_player_screen.dart';

/// "Multimedia" section of "Mi Estado": two capped grids — up to
/// [MediaLimits.maxPhotos] photos (uploaded to Storage) and up to
/// [MediaLimits.maxVideos] videos (also uploaded, played back natively via
/// [InAppVideoPlayerScreen] — never an external redirect). Purely
/// presentational: all picking/compression/upload/persistence lives in
/// [StatusScreen]'s handlers, this widget just collects taps.
class MediaManagerCard extends StatelessWidget {
  const MediaManagerCard({
    super.key,
    required this.photos,
    required this.videos,
    required this.uploadingPhoto,
    required this.uploadingVideo,
    required this.onAddPhoto,
    required this.onRemovePhoto,
    required this.onAddVideo,
    required this.onRemoveVideo,
    required this.onToggleVideoVisibility,
    required this.providerServices,
    required this.onReassignVideoService,
  });

  final List<String> photos;
  final List<MusicianVideo> videos;
  final bool uploadingPhoto;
  final bool uploadingVideo;
  final VoidCallback onAddPhoto;
  final ValueChanged<String> onRemovePhoto;
  final VoidCallback onAddVideo;
  final ValueChanged<MusicianVideo> onRemoveVideo;

  /// Called with the video and the new desired `show_in_profile` value
  /// right after the provider flips its switch.
  final void Function(MusicianVideo video, bool showInProfile) onToggleVideoVisibility;

  /// This provider's own `provider_services` listings — needed to render
  /// which one each video is tagged with (or "todos mis servicios" if
  /// [MusicianVideo.serviceId] is null). See `supabase/schema.sql` §31.
  final List<ProviderService> providerServices;

  /// Called when the provider taps a video's service tag to re-categorize
  /// it — [StatusScreen] owns the actual picker UI and persistence.
  final ValueChanged<MusicianVideo> onReassignVideoService;

  void _onAddPhotoTapped(BuildContext context) {
    if (photos.length >= MediaLimits.maxPhotos) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Ya tienes el máximo de ${MediaLimits.maxPhotos} fotos. Elimina una para agregar otra.',
            ),
          ),
        );
      return;
    }
    onAddPhoto();
  }

  void _onAddVideoTapped(BuildContext context) {
    if (videos.length >= MediaLimits.maxVideos) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Ya tienes el máximo de ${MediaLimits.maxVideos} videos. Elimina uno para agregar otro.',
            ),
          ),
        );
      return;
    }
    onAddVideo();
  }

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
            'Multimedia',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sube al menos 1 foto y 1 video para poder publicar tu perfil.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          _SectionLabel('Fotos (${photos.length}/${MediaLimits.maxPhotos})'),
          const SizedBox(height: 8),
          _MediaGrid(
            itemCount: photos.length + 1,
            itemBuilder: (context, index) {
              if (index == photos.length) {
                return _AddTile(
                  icon: Icons.add_a_photo_outlined,
                  uploading: uploadingPhoto,
                  dimmed: photos.length >= MediaLimits.maxPhotos,
                  onTap: () => _onAddPhotoTapped(context),
                );
              }
              final url = photos[index];
              return _PhotoTile(url: url, onRemove: () => onRemovePhoto(url));
            },
          ),
          const SizedBox(height: 18),
          _SectionLabel('Videos (${videos.length}/${MediaLimits.maxVideos})'),
          if (videos.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'El ícono de ojo controla si un video aparece en tu perfil público de '
              'clientes (siempre se ve aquí en tu feed, sin importar esa '
              'configuración). El ícono de tienda indica a qué servicio pertenece '
              '— tócalo para reasignarlo.',
              style: theme.textTheme.bodySmall?.copyWith(color: extension?.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          _MediaGrid(
            itemCount: videos.length + 1,
            itemBuilder: (context, index) {
              if (index == videos.length) {
                return _AddTile(
                  icon: Icons.video_call_outlined,
                  uploading: uploadingVideo,
                  dimmed: videos.length >= MediaLimits.maxVideos,
                  onTap: () => _onAddVideoTapped(context),
                );
              }
              final video = videos[index];
              return _VideoTile(
                video: video,
                serviceLabel: _serviceLabelFor(video, providerServices),
                onRemove: () => onRemoveVideo(video),
                onToggleVisibility: (visible) => onToggleVideoVisibility(video, visible),
                onTapService: () => onReassignVideoService(video),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// "Todos mis servicios" when [MusicianVideo.serviceId] is null, or the
/// matching listing's name — falls back to the same "todos" text if the
/// id doesn't match anything (e.g. the service was deleted after the
/// video was tagged; `on delete set null` means this shouldn't actually
/// happen, but a stale reference is still safer to treat as "unassigned"
/// than to crash on a missing match).
String _serviceLabelFor(MusicianVideo video, List<ProviderService> services) {
  final serviceId = video.serviceId;
  if (serviceId == null) return 'Todos mis servicios';
  for (final service in services) {
    if (service.id == serviceId) return '${service.businessName} (${service.category})';
  }
  return 'Todos mis servicios';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: extension?.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.itemCount, required this.itemBuilder});

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: itemBuilder,
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.icon,
    required this.uploading,
    required this.dimmed,
    required this.onTap,
  });

  final IconData icon;
  final bool uploading;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final accent = dimmed
        ? (extension?.textSecondary ?? Colors.grey)
        : AppColors.profileAccent;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: uploading ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: extension?.inputFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: uploading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.profileAccent,
                  ),
                ),
              )
            : Icon(icon, color: accent, size: 26),
      ),
    );
  }
}

/// Network image with a subtle spinner overlaid while it loads, instead of
/// a flat black tile — shared by photo thumbnails and video thumbnails.
class _LoadingNetworkImage extends StatelessWidget {
  const _LoadingNetworkImage({required this.url, required this.errorChild});

  final String url;
  final Widget errorChild;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => errorChild,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black12),
            const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.url, required this.onRemove});

  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _LoadingNetworkImage(
              url: url,
              errorChild: Container(
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
        _DeleteBadge(onTap: onRemove),
      ],
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.video,
    required this.serviceLabel,
    required this.onRemove,
    required this.onToggleVisibility,
    required this.onTapService,
  });

  final MusicianVideo video;
  final String serviceLabel;
  final VoidCallback onRemove;
  final ValueChanged<bool> onToggleVisibility;
  final VoidCallback onTapService;

  @override
  Widget build(BuildContext context) {
    // Falls back to the generic placeholder for videos uploaded before
    // `musician_videos.thumbnail_url` existed.
    final thumbnail = video.thumbnailUrl;

    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      InAppVideoPlayerScreen(videoUrl: video.videoUrl),
                ),
              ),
              child: thumbnail != null
                  ? _LoadingNetworkImage(
                      url: thumbnail,
                      errorChild: const _VideoPlaceholder(),
                    )
                  : const _VideoPlaceholder(),
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
        _ViewsBadge(count: video.viewsCount),
        _DeleteBadge(onTap: onRemove),
        _VisibilityBadge(
          visible: video.showInProfile,
          onTap: () => onToggleVisibility(!video.showInProfile),
        ),
        _ServiceTagBadge(
          assigned: video.serviceId != null,
          label: serviceLabel,
          onTap: onTapService,
        ),
      ],
    );
  }
}

/// Compact top-left tag — shows which `provider_services` listing this
/// video is scoped to (see `supabase/schema.sql` §31), tap to reassign.
/// Same tiny-badge-instead-of-full-control reasoning as
/// [_VisibilityBadge]: a proper dropdown doesn't fit this tile.
class _ServiceTagBadge extends StatelessWidget {
  const _ServiceTagBadge({
    required this.assigned,
    required this.label,
    required this.onTap,
  });

  final bool assigned;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 4,
      left: 4,
      child: Tooltip(
        message: assigned ? 'Servicio: $label' : 'Sin asignar: $label',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            child: Icon(
              assigned ? Icons.storefront_outlined : Icons.help_outline,
              size: 14,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact bottom-right toggle — lets the provider hide this one video
/// from the client-facing "Portafolio" tab (`ServiceDetailScreen`)
/// without deleting it from their own gallery. A tappable badge instead
/// of a full [Switch]: a real switch's ~48dp default touch target
/// doesn't fit next to [_ViewsBadge]/[_DeleteBadge] on a ~110dp tile: this
/// keeps the same square footprint every other tile already uses.
class _VisibilityBadge extends StatelessWidget {
  const _VisibilityBadge({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 4,
      right: 4,
      child: Tooltip(
        message: visible
            ? 'Visible en tu perfil de clientes'
            : 'Solo visible en tu feed de músico, no aparece para clientes',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: visible ? AppColors.profileAccent : Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Icon(
              visible ? Icons.visibility : Icons.visibility_off,
              size: 14,
              color: visible ? Colors.black : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: const Icon(
        Icons.smart_display_outlined,
        color: Colors.white54,
        size: 28,
      ),
    );
  }
}

class _ViewsBadge extends StatelessWidget {
  const _ViewsBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 4,
      left: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.visibility_outlined,
              size: 12,
              color: Colors.white,
            ),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteBadge extends StatelessWidget {
  const _DeleteBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 4,
      right: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}
