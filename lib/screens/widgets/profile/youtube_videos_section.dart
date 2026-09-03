import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/youtube_rss_service.dart';
import '../../youtube_in_app_player_screen.dart';

/// Auto-populated "Videos de YouTube" strip on [MusicianDetailScreen]: reads
/// the musician's channel via [YoutubeRssService] so they never have to
/// paste individual video links. Renders nothing while [channel] is empty,
/// still loading with no result yet, or the feed comes back empty — callers
/// can drop this in unconditionally.
class YoutubeVideosSection extends StatefulWidget {
  const YoutubeVideosSection({super.key, required this.channel});

  final String channel;

  @override
  State<YoutubeVideosSection> createState() => _YoutubeVideosSectionState();
}

class _YoutubeVideosSectionState extends State<YoutubeVideosSection> {
  static const YoutubeRssService _service = YoutubeRssService();

  late Future<List<YoutubeVideo>> _videosFuture = _fetch();

  Future<List<YoutubeVideo>> _fetch() => widget.channel.isEmpty
      ? Future.value(const [])
      : _service.fetchLatestVideos(widget.channel);

  @override
  void didUpdateWidget(YoutubeVideosSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The musician's own [Musician] instance is only built once per screen
    // load today, so this never fires in practice — kept so a future
    // "refresh profile in place" doesn't silently show a stale channel's
    // videos after the field changes.
    if (oldWidget.channel != widget.channel) {
      setState(() => _videosFuture = _fetch());
    }
  }

  void _open(YoutubeVideo video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => YoutubeInAppPlayerScreen(videoId: video.videoId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channel.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<YoutubeVideo>>(
      future: _videosFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final videos = snapshot.data ?? const [];
        if (videos.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Videos de YouTube',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 168,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: videos.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final video = videos[index];
                  return _VideoCard(
                    video: video,
                    onTap: () => _open(video),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video, required this.onTap});

  final YoutubeVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      video.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.black12,
                        alignment: Alignment.center,
                        child: const Icon(Icons.smart_display_outlined),
                      ),
                    ),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: extension?.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
