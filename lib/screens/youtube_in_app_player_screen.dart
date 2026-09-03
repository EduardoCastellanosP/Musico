import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../services/youtube_rss_service.dart';

/// Full-screen embedded YouTube player — the in-app counterpart to
/// [InAppVideoPlayerScreen] for links sourced from a musician's YouTube
/// channel rather than their own Supabase-hosted upload. Pushed from
/// [YoutubeVideosSection] instead of `launchUrl`, so watching a channel
/// video never leaves the app.
///
/// Minimalist by design: no AppBar/title, no YouTube controls/annotations —
/// just the video, autoplaying, with a small overlay back button. [videoId]
/// accepts either a bare id or a full URL (`watch?v=`, `/shorts/`, `/embed/`,
/// `youtu.be/...`) — [YoutubeRssService.extractVideoId] normalizes either
/// form the same way, so a Short and a standard upload play identically.
class YoutubeInAppPlayerScreen extends StatefulWidget {
  const YoutubeInAppPlayerScreen({super.key, required this.videoId});

  final String videoId;

  @override
  State<YoutubeInAppPlayerScreen> createState() =>
      _YoutubeInAppPlayerScreenState();
}

class _YoutubeInAppPlayerScreenState extends State<YoutubeInAppPlayerScreen> {
  late final String _videoId =
      YoutubeRssService.extractVideoId(widget.videoId) ?? widget.videoId;

  late final YoutubePlayerController _controller = YoutubePlayerController.fromVideoId(
    videoId: _videoId,
    autoPlay: true,
    params: const YoutubePlayerParams(
      showControls: false,
      showFullscreenButton: false,
      showVideoAnnotations: false,
    ),
  );

  /// Real width/height for [_videoId] — vertical for a Short, 16:9
  /// otherwise. Starts at 16:9 and adjusts once the lookup resolves, so
  /// autoplay never waits on it.
  double _aspectRatio = 16 / 9;

  @override
  void initState() {
    super.initState();
    const YoutubeRssService().fetchAspectRatio(_videoId).then((ratio) {
      if (mounted) setState(() => _aspectRatio = ratio);
    });
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: YoutubePlayer(
              controller: _controller,
              aspectRatio: _aspectRatio,
              backgroundColor: Colors.black,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
