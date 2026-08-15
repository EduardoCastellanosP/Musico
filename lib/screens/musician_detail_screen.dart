import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../models/musician.dart';
import '../models/musician_photo.dart';
import '../repositories/musician_repository.dart';
import 'photo_viewer_screen.dart';
import 'widgets/dashboard/genre_badge.dart';

/// Full-screen profile a contratante sees after tapping a [MusicianCard]:
/// every directory fact plus the musician's live-performance photo
/// portfolio, so organizers can judge the musician's work before reaching out.
class MusicianDetailScreen extends StatefulWidget {
  const MusicianDetailScreen({super.key, required this.musician});

  final Musician musician;

  @override
  State<MusicianDetailScreen> createState() => _MusicianDetailScreenState();
}

class _MusicianDetailScreenState extends State<MusicianDetailScreen> {
  final MusicianRepository _repository = MusicianRepository();

  List<MusicianPhoto> _photos = const [];
  bool _loadingPhotos = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = await _repository.fetchPhotos(widget.musician.id);
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loadingPhotos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPhotos = false);
    }
  }

  Future<void> _contact({required bool isWhatsApp}) async {
    final musician = widget.musician;
    final uri = isWhatsApp ? musician.whatsappUri : musician.callUri;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) return;
    unawaited(
      _repository.logContactEvent(
        musicianId: musician.id,
        contactType: isWhatsApp ? 'whatsapp' : 'call',
      ),
    );
  }

  void _openPhoto(MusicianPhoto photo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(imageUrl: photo.imageUrl),
      ),
    );
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
                  GenreBadge(genre: musician.genre),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                [
                  if (musician.instrument.isNotEmpty) musician.instrument,
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
                  child: FilledButton.icon(
                    onPressed: musician.hasPhone
                        ? () => _contact(isWhatsApp: true)
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: const Text('WhatsApp'),
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
          ],
        ),
      ),
    );
  }

  Widget _buildGallery(ThemeData theme, AppThemeExtension? extension) {
    if (_loadingPhotos) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }

    if (_photos.isEmpty) {
      return Text(
        'Este músico aún no agregó fotos a su portafolio.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: extension?.textSecondary,
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final photo = _photos[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _openPhoto(photo),
            child: Image.network(
              photo.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
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
