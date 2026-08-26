import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_theme.dart';
import '../models/video_feed_item.dart';
import '../repositories/musician_repository.dart';

/// Reels/TikTok-style vertical feed of every musician's uploaded videos,
/// newest first. Only the on-screen page's [VideoPlayerController] is ever
/// playing — [_ensureControllersAround] keeps at most 3 controllers alive
/// (current ± 1, to make the next swipe instant) and disposes the rest, so
/// scrolling through a long feed never accumulates decoders/memory.
///
/// The `State` is public ([VideoFeedScreenState], not the usual
/// underscore-prefixed convention) so [HomeShell] can hold a `GlobalKey`
/// to it and call [pauseCurrent] the moment the bottom nav switches away
/// from this tab — `IndexedStack` keeps this screen mounted (so playback
/// position/feed scroll survive tab switches) but does nothing on its own
/// to stop an off-screen video's audio.
class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => VideoFeedScreenState();
}

class VideoFeedScreenState extends State<VideoFeedScreen> {
  final MusicianRepository _repository = MusicianRepository();
  final PageController _pageController = PageController();

  final List<VideoFeedItem> _items = [];
  final Map<int, VideoPlayerController> _controllers = {};
  final Set<String> _likedVideoIds = {};
  final Set<String> _followedMusicianIds = {};

  int _currentIndex = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _reachedEnd = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  /// Pauses whichever video is currently playing — called by [HomeShell]
  /// when the user taps away from the "Videos" tab, so the audio doesn't
  /// keep playing under the "Directorio" tab.
  void pauseCurrent() {
    _controllers[_currentIndex]?.pause();
  }

  /// Resumes the current video — called by [HomeShell] when the user taps
  /// back into the "Videos" tab.
  void resumeCurrent() {
    final controller = _controllers[_currentIndex];
    if (controller != null && controller.value.isInitialized) {
      controller.play();
    }
  }

  Future<void> _loadInitial() async {
    try {
      final items = await _repository.fetchVideoFeed();
      final liked = await _repository.fetchLikedVideoIds(
        items.map((item) => item.video.id).toList(),
      );
      final followed = await _repository.fetchFollowedMusicianIds(
        items.map((item) => item.musicianId).toSet().toList(),
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _likedVideoIds.addAll(liked);
        _followedMusicianIds.addAll(followed);
        _loading = false;
        _reachedEnd = items.isEmpty;
      });
      _ensureControllersAround(0);
      if (items.isNotEmpty) _countView(0);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No pudimos cargar el feed de videos.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _reachedEnd || _items.isEmpty) return;
    _loadingMore = true;
    try {
      final more = await _repository.fetchVideoFeed(
        before: _items.last.video.createdAt,
      );
      final liked = await _repository.fetchLikedVideoIds(
        more.map((item) => item.video.id).toList(),
      );
      final followed = await _repository.fetchFollowedMusicianIds(
        more.map((item) => item.musicianId).toSet().toList(),
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(more);
        _likedVideoIds.addAll(liked);
        _followedMusicianIds.addAll(followed);
        _reachedEnd = more.isEmpty;
      });
    } catch (_) {
      // Silent: the feed just stops growing for this session; scrolling
      // back up to already-loaded videos still works fine.
    } finally {
      _loadingMore = false;
    }
  }

  void _ensureControllersAround(int index) {
    final keep = <int>{
      index - 1,
      index,
      index + 1,
    }..removeWhere((i) => i < 0 || i >= _items.length);

    final toRemove = _controllers.keys.where((i) => !keep.contains(i)).toList();
    for (final i in toRemove) {
      _controllers.remove(i)?.dispose();
    }

    for (final i in keep) {
      _controllers.putIfAbsent(i, () {
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(_items[i].video.videoUrl),
        )..setLooping(true);
        controller.initialize().then((_) {
          if (!mounted || !_controllers.containsKey(i)) return;
          if (i == _currentIndex) controller.play();
          setState(() {});
        });
        return controller;
      });
    }

    for (final entry in _controllers.entries) {
      if (entry.key == index) {
        if (entry.value.value.isInitialized) entry.value.play();
      } else {
        entry.value.pause();
      }
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _ensureControllersAround(index);
    _countView(index);
    if (index >= _items.length - 2) _loadMore();
  }

  void _countView(int index) {
    unawaited(_repository.incrementVideoView(_items[index].video.id));
  }

  Future<void> _contactWhatsApp(VideoFeedItem item) async {
    if (!item.hasPhone) return;
    final launched = await launchUrl(
      item.whatsappUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) return;
    unawaited(
      _repository.logContactEvent(
        musicianId: item.musicianId,
        contactType: 'whatsapp',
      ),
    );
  }

  /// Optimistic like toggle: flips [_likedVideoIds] (and therefore the
  /// heart icon) immediately, fires the write in the background, and rolls
  /// the flip back only if that write fails.
  Future<void> _toggleLike(VideoFeedItem item) async {
    final id = item.video.id;
    final wasLiked = _likedVideoIds.contains(id);
    setState(() {
      wasLiked ? _likedVideoIds.remove(id) : _likedVideoIds.add(id);
    });
    try {
      if (wasLiked) {
        await _repository.unlikeVideo(id);
      } else {
        await _repository.likeVideo(id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        wasLiked ? _likedVideoIds.add(id) : _likedVideoIds.remove(id);
      });
    }
  }

  /// Same optimistic-then-rollback shape as [_toggleLike], for "Seguir".
  Future<void> _toggleFollow(VideoFeedItem item) async {
    final id = item.musicianId;
    final wasFollowing = _followedMusicianIds.contains(id);
    setState(() {
      wasFollowing
          ? _followedMusicianIds.remove(id)
          : _followedMusicianIds.add(id);
    });
    try {
      if (wasFollowing) {
        await _repository.unfollowMusician(id);
      } else {
        await _repository.followMusician(id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        wasFollowing
            ? _followedMusicianIds.add(id)
            : _followedMusicianIds.remove(id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.white70)),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Todavía no hay videos en el feed. Sube el tuyo desde "Mi Estado".',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _items.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          final item = _items[index];
          return _VideoFeedPage(
            item: item,
            controller: _controllers[index],
            isLiked: _likedVideoIds.contains(item.video.id),
            isFollowing: _followedMusicianIds.contains(item.musicianId),
            onLike: () => _toggleLike(item),
            onFollow: () => _toggleFollow(item),
            onContact: () => _contactWhatsApp(item),
          );
        },
      ),
    );
  }
}

class _VideoFeedPage extends StatelessWidget {
  const _VideoFeedPage({
    required this.item,
    required this.controller,
    required this.isLiked,
    required this.isFollowing,
    required this.onLike,
    required this.onFollow,
    required this.onContact,
  });

  final VideoFeedItem item;
  final VideoPlayerController? controller;
  final bool isLiked;
  final bool isFollowing;
  final VoidCallback onLike;
  final VoidCallback onFollow;
  final VoidCallback onContact;

  void _togglePlay() {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ready = c != null && c.value.isInitialized;

    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (ready)
            // Fills the whole screen and crops (no letterboxing), matching
            // the TikTok/Reels "video fills the frame" look — the same
            // FittedBox(fit: cover) shape LoginScreen already uses for its
            // background video.
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          // Bottom gradient so the overlay text/buttons stay readable
          // regardless of how bright the underlying video frame is.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 260,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              child: _VideoFeedOverlay(
                item: item,
                isLiked: isLiked,
                isFollowing: isFollowing,
                onLike: onLike,
                onFollow: onFollow,
                onContact: onContact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Profile row + action-button row stacked above the bottom gradient —
/// exactly the two blocks the design calls for, nothing extra.
class _VideoFeedOverlay extends StatelessWidget {
  const _VideoFeedOverlay({
    required this.item,
    required this.isLiked,
    required this.isFollowing,
    required this.onLike,
    required this.onFollow,
    required this.onContact,
  });

  final VideoFeedItem item;
  final bool isLiked;
  final bool isFollowing;
  final VoidCallback onLike;
  final VoidCallback onFollow;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileRow(item: item),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _OutlinedPillButton(
                  icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  iconColor: isLiked ? Colors.red : Colors.white,
                  label: 'Me gusta',
                  onTap: onLike,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OutlinedPillButton(
                  icon: isFollowing
                      ? Icons.person_remove_alt_1_rounded
                      : Icons.person_add_alt_1_rounded,
                  iconColor: Colors.white,
                  label: isFollowing ? 'Siguiendo' : 'Seguir',
                  onTap: onFollow,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: item.hasPhone ? onContact : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF25D366).withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                  label: const Text(
                    'Contactar',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.item});

  final VideoFeedItem item;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = item.avatarUrl;
    final primaryGenre = item.genres.isNotEmpty ? item.genres.first : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          padding: const EdgeInsets.all(1.5),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.accent.withValues(alpha: 0.2),
            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? NetworkImage(avatarUrl)
                : null,
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? const Icon(Icons.person, color: Colors.white, size: 20)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      item.musicianName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  if (primaryGenre != null) ...[
                    const SizedBox(width: 8),
                    _GenrePill(label: primaryGenre),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.music_note_rounded, size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      item.subtitle.isNotEmpty ? item.subtitle : 'Músico',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  if (item.city.isNotEmpty) ...[
                    const Text('  •  ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const Icon(Icons.location_on_rounded, size: 14, color: Colors.white70),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        item.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bright-yellow/black genre pill — deliberately its own small widget
/// instead of reusing the dashboard's `GenreBadge` (gold/teal, bordered),
/// since this screen's spec calls for a solid, high-contrast pill instead.
class _GenrePill extends StatelessWidget {
  const _GenrePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD60A),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _OutlinedPillButton extends StatelessWidget {
  const _OutlinedPillButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.grey.shade800),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 16, color: iconColor),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
