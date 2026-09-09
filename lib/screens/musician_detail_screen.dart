import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/musician.dart';
import '../models/musician_video.dart';
import '../repositories/musician_repository.dart';
import 'chat_screen.dart';
import 'in_app_video_player_screen.dart';
import 'photo_viewer_screen.dart';
import 'widgets/complete_profile_prompt.dart';
import 'widgets/profile/media_grid.dart';
import 'widgets/profile/people_list_sheet.dart';
import 'widgets/profile/profile_header.dart';

/// Full-screen profile a contratante sees after tapping a [MusicianCard]:
/// [ProfileHeader] (cover photo, avatar, identity, availability) followed
/// by the action buttons and a unified photo+video [MediaGrid]. `photos`/
/// `videos` are already part of [musician] (loaded with the rest of the
/// directory row) — nothing extra to fetch here.
class MusicianDetailScreen extends StatefulWidget {
  const MusicianDetailScreen({super.key, required this.musician});

  final Musician musician;

  @override
  State<MusicianDetailScreen> createState() => _MusicianDetailScreenState();
}

class _MusicianDetailScreenState extends State<MusicianDetailScreen> {
  final MusicianRepository _repository = MusicianRepository();

  /// Local, mutable copy of [Musician.videos] so a view count can bump in
  /// place the instant playback starts, without needing to refetch the
  /// whole profile.
  late List<MusicianVideo> _videos;

  bool _isFollowing = false;
  ({int followers, int likes}) _followStats = (followers: 0, likes: 0);

  @override
  void initState() {
    super.initState();
    _videos = List<MusicianVideo>.from(widget.musician.videos);
    _loadFollowState();
  }

  Future<void> _loadFollowState() async {
    final musicianId = widget.musician.id;
    final followedFuture = _repository.fetchFollowedMusicianIds([musicianId]);
    final statsFuture = _repository.fetchPublicFollowStats(musicianId);
    final followed = await followedFuture;
    final stats = await statsFuture;
    if (!mounted) return;
    setState(() {
      _isFollowing = followed.contains(musicianId);
      _followStats = stats;
    });
  }

  /// Optimistic toggle — same shape as [VideoFeedScreenState._toggleFollow]:
  /// flip the button immediately, roll back only if the write fails.
  ///
  /// Guards against following yourself: [MusicianRepository.followMusician]
  /// already no-ops server-side for this case, but without this check the
  /// button would still optimistically (and incorrectly) flip to
  /// "Siguiendo" since that no-op doesn't throw.
  Future<void> _toggleFollow() async {
    if (widget.musician.id == _repository.currentUserId) return;
    final wasFollowing = _isFollowing;
    setState(() => _isFollowing = !wasFollowing);
    try {
      if (wasFollowing) {
        await _repository.unfollowMusician(widget.musician.id);
      } else {
        await _repository.followMusician(widget.musician.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFollowing = wasFollowing);
    }
  }

  /// El número del músico ya no se expone directamente (privacidad):
  /// contactar abre el chat interno. Mismo gate de perfil completo que
  /// antes usaba WhatsApp/Llamar.
  Future<void> _sendMessage() async {
    if (!await _repository.currentProfileCanContact()) {
      if (!mounted) return;
      await showCompleteProfilePrompt(context);
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(musician: widget.musician)),
    );
  }

  void _openPhoto(String url) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PhotoViewerScreen(imageUrl: url)));
  }

  void _openVideo(MusicianVideo video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InAppVideoPlayerScreen(
          videoUrl: video.videoUrl,
          onViewed: () => _onVideoViewed(video),
        ),
      ),
    );
  }

  /// Bumps the local counter immediately (so the badge updates the instant
  /// playback starts), then fires [MusicianRepository.incrementVideoView]
  /// asynchronously and silently — a failed view count is never worth
  /// interrupting or blocking playback for.
  Future<void> _onVideoViewed(MusicianVideo video) async {
    setState(() {
      _videos = _videos
          .map(
            (v) =>
                v.id == video.id ? v.copyWith(viewsCount: v.viewsCount + 1) : v,
          )
          .toList();
    });
    try {
      await _repository.incrementVideoView(video.id);
    } catch (_) {
      // Silent by design — see doc comment above.
    }
  }

  @override
  Widget build(BuildContext context) {
    final musician = widget.musician;
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: ProfileHeader(
                  musician: musician,
                  backgroundImageUrl: musician.coverUrl ??
                      (musician.photos.isNotEmpty
                          ? musician.photos.first
                          : null),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                sliver: SliverList.list(
                  children: [
                    if (musician.services.isNotEmpty) ...[
                      Text(
                        'Servicios',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: extension?.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final service in musician.services)
                            Chip(
                              label: Text(service),
                              backgroundColor: extension?.inputFill,
                              side: BorderSide.none,
                              labelStyle: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (musician.serviceDescription.isNotEmpty) ...[
                      Text(
                        musician.descriptionSectionTitle,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: extension?.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        musician.serviceDescription,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (musician.coverageCities.isNotEmpty) ...[
                      Text(
                        'También toca en',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: extension?.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final city in musician.coverageCities)
                            Chip(
                              label: Text(city),
                              backgroundColor: extension?.inputFill,
                              side: BorderSide.none,
                              labelStyle: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    _ActionButtonsRow(
                      isFollowing: _isFollowing,
                      onToggleFollow: _toggleFollow,
                      onSendMessage: _sendMessage,
                    ),
                    const SizedBox(height: 16),
                    _FollowStatsRow(
                      musicianId: musician.id,
                      repository: _repository,
                      stats: _followStats,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Multimedia',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: MediaGrid(
                  photos: musician.photos,
                  videos: _videos,
                  onTapPhoto: _openPhoto,
                  onTapVideo: _openVideo,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
          // ProfileHeader replaces the usual AppBar, so this floating
          // circle is what lets the user actually go back — same pattern
          // as VideoFeedScreen's back button.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _BackButton(onTap: () => Navigator.of(context).pop()),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// "N seguidores · N me gusta" for the musician being viewed — same shape
/// and tap behavior as [DashboardHeader]'s own-profile row, just fed by
/// [MusicianRepository.fetchPublicFollowStats] for a third-party profile
/// instead of [MusicianRepository.fetchContactStats] for the logged-in one.
class _FollowStatsRow extends StatelessWidget {
  const _FollowStatsRow({
    required this.musicianId,
    required this.repository,
    required this.stats,
  });

  final String musicianId;
  final MusicianRepository repository;
  final ({int followers, int likes}) stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: extension?.textSecondary,
      fontWeight: FontWeight.w600,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showPeopleListSheet(
            context,
            title: 'Seguidores',
            fetchPeople: () => repository.fetchFollowers(musicianId),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Text('${stats.followers} seguidores', style: textStyle),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showPeopleListSheet(
            context,
            title: 'Me gusta',
            fetchPeople: () => repository.fetchVideoLikers(musicianId),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Text('${stats.likes} me gusta', style: textStyle),
          ),
        ),
      ],
    );
  }
}

/// "Siguiendo/Seguir" plus a single "Enviar Mensaje" CTA — WhatsApp/Llamar
/// were removed so the musician's phone number is never exposed directly in
/// the directory; contacting now goes through [_MusicianDetailScreenState._sendMessage]
/// (chat interno, pendiente de implementar).
class _ActionButtonsRow extends StatelessWidget {
  const _ActionButtonsRow({
    required this.isFollowing,
    required this.onToggleFollow,
    required this.onSendMessage,
  });

  final bool isFollowing;
  final VoidCallback onToggleFollow;
  final VoidCallback onSendMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();
    final borderColor =
        extension?.textSecondary.withValues(alpha: 0.3) ?? Colors.grey;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onToggleFollow,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              foregroundColor:
                  isFollowing ? AppColors.accent : extension?.textSecondary,
              side: BorderSide(color: isFollowing ? AppColors.accent : borderColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: Icon(
              isFollowing
                  ? Icons.person_remove_alt_1_rounded
                  : Icons.person_add_alt_1_rounded,
              size: 16,
            ),
            label: Text(
              isFollowing ? 'Siguiendo' : 'Seguir',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: onSendMessage,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_rounded, size: 16),
            label: const Text(
              'Enviar Mensaje',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
