import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/musician_video.dart';

/// Unified photo+video portfolio grid — a single [SliverGrid] instead of
/// two separate "Galería"/"Videos" sections, so a musician's uploads read
/// as one continuous body of work. Drop directly into a [CustomScrollView]
/// (it returns a sliver, not a boxed widget); renders its own empty state
/// when there's nothing to show, so callers never need an `if` around it.
class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.photos,
    required this.videos,
    required this.onTapPhoto,
    required this.onTapVideo,
  });

  final List<String> photos;
  final List<MusicianVideo> videos;
  final ValueChanged<String> onTapPhoto;
  final ValueChanged<MusicianVideo> onTapVideo;

  @override
  Widget build(BuildContext context) {
    final items = <_MediaItem>[
      for (final photo in photos) _MediaItem.photo(photo),
      for (final video in videos) _MediaItem.video(video),
    ];

    if (items.isEmpty) {
      final theme = Theme.of(context);
      final extension = theme.extension<AppThemeExtension>();
      return SliverToBoxAdapter(
        child: Text(
          'Aún no agregó fotos ni videos a su portafolio.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: extension?.textSecondary,
          ),
        ),
      );
    }

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: switch (item.kind) {
              _MediaKind.photo => _PhotoTile(
                url: item.photoUrl!,
                onTap: () => onTapPhoto(item.photoUrl!),
              ),
              _MediaKind.video => _VideoTile(
                video: item.video!,
                onTap: () => onTapVideo(item.video!),
              ),
            },
          );
        },
        childCount: items.length,
      ),
    );
  }
}

enum _MediaKind { photo, video }

/// Tags each grid cell as a photo or a video so [MediaGrid] can render one
/// heterogeneous list without a separate model class per media type.
class _MediaItem {
  const _MediaItem.photo(String url) : photoUrl = url, video = null, kind = _MediaKind.photo;

  const _MediaItem.video(MusicianVideo this.video)
    : photoUrl = null,
      kind = _MediaKind.video;

  final _MediaKind kind;
  final String? photoUrl;
  final MusicianVideo? video;
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.black12,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined),
        ),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: Colors.black12,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      ),
    );
  }
}

/// Video tile whose "thumbnail" is the real first frame of the clip,
/// instead of a generic placeholder icon or a YouTube-only thumbnail URL.
///
/// ponytail: this initializes a full [VideoPlayerController] per tile (and
/// therefore starts buffering the actual video) just to paint frame zero —
/// simple and needs no new dependency or backend work, but it costs real
/// bandwidth for a thumbnail. Fine at this app's per-profile cap (≤5
/// videos); upgrade to a stored thumbnail (extracted server-side on
/// upload) if the grid ever needs to show many more videos at once.
class _VideoTile extends StatefulWidget {
  const _VideoTile({required this.video, required this.onTap});

  final MusicianVideo video;
  final VoidCallback onTap;

  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _initThumbnail();
  }

  Future<void> _initThumbnail() async {
    final uri = Uri.tryParse(widget.video.videoUrl);
    if (uri == null) return;

    final controller = VideoPlayerController.networkUrl(uri);
    try {
      await controller.initialize();
      await controller.seekTo(Duration.zero);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return InkWell(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            )
          else
            const ColoredBox(
              color: Colors.black87,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
          Positioned(
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
                    '${widget.video.viewsCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
