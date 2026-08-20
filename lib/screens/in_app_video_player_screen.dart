import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_theme.dart';

/// Full-screen native player shared by [MediaManagerCard] (the musician
/// previewing their own upload — no view counted) and
/// [MusicianDetailScreen] (a contratante watching a public profile's video
/// — [onViewed] fires once here). Every "cero redirecciones externas"
/// requirement funnels through this one widget instead of `launchUrl`.
///
/// Both native controllers are created lazily — only when this screen is
/// actually pushed, i.e. only when the user taps a video tile — and are
/// torn down in [dispose], so a profile with 3 unwatched videos never costs
/// more than 3 small thumbnail tiles worth of memory.
class InAppVideoPlayerScreen extends StatefulWidget {
  const InAppVideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.onViewed,
  });

  final String videoUrl;

  /// Called at most once, right after the player finishes initializing
  /// (i.e. is about to start playing) — never on the admin preview path.
  final VoidCallback? onViewed;

  @override
  State<InAppVideoPlayerScreen> createState() => _InAppVideoPlayerScreenState();
}

class _InAppVideoPlayerScreenState extends State<InAppVideoPlayerScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _hasError = false;
  bool _viewCounted = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

 Future<void> _initialize() async {
    // 1. Validación de seguridad para calmar al escáner SAST
    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    
    try {
      await controller.initialize();
      // The screen may have been popped while `initialize()` was still in
      // flight (slow network + an impatient back tap) — bail out instead
      // of calling setState on an unmounted State, and dispose the
      // controller we just created so it doesn't leak.
      if (!mounted) {
        await controller.dispose();
        return;
      }

      final chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.profileAccent,
          handleColor: AppColors.profileAccent,
        ),
      );

      setState(() {
        _videoController = controller;
        _chewieController = chewieController;
      });
      _countViewOnce();
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _hasError = true);
    }
  }

  void _countViewOnce() {
    if (_viewCounted) return;
    _viewCounted = true;
    widget.onViewed?.call();
  }

  @override
  void dispose() {
    // Order matters: Chewie's controller wraps the video controller, so it
    // must go first, then the underlying native player resource.
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: _hasError
            ? const Text(
                'No pudimos cargar el video.',
                style: TextStyle(color: Colors.white),
              )
            : _chewieController == null
            ? const CircularProgressIndicator(color: AppColors.profileAccent)
            : Chewie(controller: _chewieController!),
      ),
    );
  }
}
