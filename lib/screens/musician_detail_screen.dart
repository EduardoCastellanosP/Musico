import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/whatsapp.dart';
import '../core/theme/app_theme.dart';
import '../models/musician.dart';
import '../models/musician_video.dart';
import '../repositories/musician_repository.dart';
import 'in_app_video_player_screen.dart';
import 'photo_viewer_screen.dart';
import 'widgets/profile/media_grid.dart';
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

  @override
  void initState() {
    super.initState();
    _videos = List<MusicianVideo>.from(widget.musician.videos);
    _loadFollowState();
  }

  Future<void> _loadFollowState() async {
    final followed = await _repository.fetchFollowedMusicianIds([
      widget.musician.id,
    ]);
    if (!mounted) return;
    setState(() => _isFollowing = followed.contains(widget.musician.id));
  }

  /// Optimistic toggle — same shape as [VideoFeedScreenState._toggleFollow]:
  /// flip the button immediately, roll back only if the write fails.
  Future<void> _toggleFollow() async {
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

  Future<void> _contact({required bool isWhatsApp}) async {
    final musician = widget.musician;
    final uri = isWhatsApp ? musician.whatsappUri : musician.callUri;

    // Validación SAST: Asegurar que el esquema de la URI sea un canal seguro/permitido
    if (!['https', 'http', 'tel', 'whatsapp'].contains(uri.scheme)) {
      debugPrint('🛑 SEGURIDAD: Esquema bloqueado -> ${uri.scheme}');
      return;
    }

    if (await canLaunchUrl(uri)) {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) return;

      unawaited(
        _repository.logContactEvent(
          musicianId: musician.id,
          contactType: isWhatsApp ? 'whatsapp' : 'call',
        ),
      );
    }
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
                  backgroundImageUrl:
                      musician.photos.isNotEmpty ? musician.photos.first : null,
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
                        musician.serviceDescription,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: extension?.textSecondary,
                        ),
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
                      onWhatsApp: musician.hasPhone
                          ? () => _contact(isWhatsApp: true)
                          : null,
                      onCall: musician.hasPhone
                          ? () => _contact(isWhatsApp: false)
                          : null,
                    ),
                    const SizedBox(height: 28),
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

/// "Siguiendo/Seguir", WhatsApp and Llamar as one evenly-distributed row —
/// same three-column shape as [VideoFeedScreen]'s action row, for a
/// consistent action pattern across the app.
class _ActionButtonsRow extends StatelessWidget {
  const _ActionButtonsRow({
    required this.isFollowing,
    required this.onToggleFollow,
    required this.onWhatsApp,
    required this.onCall,
  });

  final bool isFollowing;
  final VoidCallback onToggleFollow;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onCall;

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
          child: FilledButton(
            onPressed: onWhatsApp,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  const Color(0xFF25D366).withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset('assets/images/logowpp.svg', width: 18, height: 18),
                const SizedBox(width: 6),
                const Text(
                  kWhatsAppShortLabel,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onCall,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: borderColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.call_rounded, size: 16),
            label: const Text(
              'Llamar',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
