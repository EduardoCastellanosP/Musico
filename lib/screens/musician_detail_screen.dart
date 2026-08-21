import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/app_logger.dart';
import '../core/constants/whatsapp.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/video_thumbnail.dart';
import '../models/musician.dart';
import '../models/musician_video.dart';
import '../repositories/musician_repository.dart';
import 'in_app_video_player_screen.dart';
import 'photo_viewer_screen.dart';
import 'widgets/dashboard/genre_badge.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Full-screen profile a contratante sees after tapping a [MusicianCard]:
/// every directory fact plus the musician's photo/video portfolio, so
/// organizers can judge the musician's work before reaching out. `photos`/
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

  @override
  void initState() {
    super.initState();
    _videos = List<MusicianVideo>.from(widget.musician.videos);
  }

 Future<void> _contact({required bool isWhatsApp}) async {
    final musician = widget.musician;
    final uri = isWhatsApp ? musician.whatsappUri : musician.callUri;
    
    // Validación SAST: Asegurar que el esquema de la URI sea un canal seguro/permitido
    if (!['https', 'http', 'tel', 'whatsapp'].contains(uri.scheme)) {
      debugPrint("🛑 SEGURIDAD: Esquema bloqueado -> ${uri.scheme}");
      return;
    }
    
    // Verificar si el dispositivo puede manejar la acción de forma segura
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
      appBar: AppBar(title: Text(musician.fullName)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Center(child: _DetailAvatar(musician: musician)),
            const SizedBox(height: 16),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    musician.fullName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  GenreBadge(genres: musician.genres),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                [
                  if (musician.instruments.isNotEmpty)
                    musician.instrumentsSummary
                  else if (musician.services.isNotEmpty)
                    musician.services.join(' · '),
                  if (musician.city.isNotEmpty) musician.city,
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: extension?.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RatingStars(rating: musician.rating),
                  const SizedBox(width: 6),
                  Text(
                    '${musician.rating.toStringAsFixed(1)} (${musician.reviewsCount})',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: extension?.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '· ${musician.experienceYears} años de experiencia',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: extension?.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _AvailabilityBanner(musician: musician),
            if (musician.services.isNotEmpty) ...[
              const SizedBox(height: 16),
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
            ],
            if (musician.serviceDescription.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                musician.serviceDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: extension?.textSecondary,
                ),
              ),
            ],
            if (musician.coverageCities.isNotEmpty) ...[
              const SizedBox(height: 16),
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
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
  child: FilledButton(
    onPressed: musician.hasPhone
        ? () => _contact(isWhatsApp: true)
        : null,
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xFF25D366), // Color verde WhatsApp
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          'assets/images/logowpp.svg',
          width: 20,
          height: 20,
          // Forzamos el icono a blanco para que resalte en el fondo verde
          // colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
        const SizedBox(width: 8),
        const Text(kWhatsAppShortLabel),
      ],
    ),
  ),
),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: musician.hasPhone
                        ? () => _contact(isWhatsApp: false)
                        : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                        color:
                            extension?.textSecondary.withValues(alpha: 0.3) ??
                            Colors.grey,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: const Text('Llamar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              'Galería de presentaciones',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _buildGallery(theme, extension),
            if (_videos.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Videos',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _buildVideos(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGallery(ThemeData theme, AppThemeExtension? extension) {
    final photos = widget.musician.photos;

    if (photos.isEmpty) {
      return Text(
        'Aún no agregó fotos a su portafolio.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: extension?.textSecondary,
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final url = photos[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _openPhoto(url),
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
          ),
        );
      },
    );
  }

  Widget _buildVideos() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _videos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final video = _videos[index];
        final thumbnail = youtubeThumbnail(video.videoUrl);
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _openVideo(video),
            child: Stack(
              children: [
                Positioned.fill(
                  child: thumbnail != null
                      ? Image.network(
                          thumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(color: Colors.black87),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: Colors.black87,
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white54,
                                ),
                              ),
                            );
                          },
                        )
                      : Container(color: Colors.black87),
                ),
                const Positioned.fill(
                  child: Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
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
                          '${video.viewsCount}',
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
          ),
        );
      },
    );
  }
}

class _DetailAvatar extends StatelessWidget {
  const _DetailAvatar({required this.musician});

  final Musician musician;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = musician.avatarUrl;

    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: AppColors.accent.withValues(alpha: 0.15),
            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                ? NetworkImage(avatarUrl)
                : null,
            child: avatarUrl == null || avatarUrl.isEmpty
                ? Text(
                    musician.initials,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: musician.isFree ? Colors.green : Colors.red,
                border: Border.all(
                  color: theme.scaffoldBackgroundColor,
                  width: 3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityBanner extends StatelessWidget {
  const _AvailabilityBanner({required this.musician});

  final Musician musician;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = musician.isFree ? Colors.green : Colors.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time_filled_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              musician.availabilityLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: musician.isFree
                    ? Colors.green.shade700
                    : Colors.red.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingStars extends StatelessWidget {
  const _RatingStars({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final threshold = index + 1;
        IconData icon;
        if (rating >= threshold) {
          icon = Icons.star_rounded;
        } else if (rating >= threshold - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_border_rounded;
        }
        return Icon(icon, size: 16, color: AppColors.accent);
      }),
    );
  }
}