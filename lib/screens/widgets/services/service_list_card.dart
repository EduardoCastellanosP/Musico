import 'package:flutter/material.dart';

import '../../../core/utils/currency.dart';
import '../../../models/provider_service.dart';
import 'service_cover_image.dart';

const _kSurface = Color(0xFF17171D);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

/// Gold "verified" checkmark badge — `provider_services.is_verified`,
/// shared by `ClientHomeScreen`'s featured carousel/list and
/// `SavedServicesScreen`'s cards.
class ServiceVerifiedBadge extends StatelessWidget {
  const ServiceVerifiedBadge({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: _kAccent, shape: BoxShape.circle),
      child: Icon(Icons.check, color: Colors.black, size: size * 0.7),
    );
  }
}

/// "★ 4.9 (87)" rating row, backed by the real
/// `provider_services.rating`/`reviews_count` columns.
class ServiceRatingRow extends StatelessWidget {
  const ServiceRatingRow({
    super.key,
    required this.rating,
    required this.reviewsCount,
    this.color = Colors.white,
  });

  final double rating;
  final int reviewsCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, color: _kAccent, size: 15),
        const SizedBox(width: 3),
        Text(
          '${rating.toStringAsFixed(1)} ($reviewsCount)',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Filled category tag — used as the corner overlay on `_FeaturedCard`'s
/// full-bleed photo, where a solid backdrop keeps the label legible over
/// whatever's in the image.
class ServiceGenreBadge extends StatelessWidget {
  const ServiceGenreBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _kAccent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Hollow/outlined category pill — transparent fill, thin amber border,
/// amber text. Used inline in [ServiceListCard]'s text column (unlike
/// [ServiceGenreBadge]'s solid corner-overlay use, there's no photo behind
/// this one to fight for contrast against).
class ServiceGenrePill extends StatelessWidget {
  const ServiceGenrePill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kAccent),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _kAccent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Heart toggle with a punchy scale-up-then-settle bounce on tap.
/// Optimistic: flips its own display immediately, calls
/// [onToggleSaved] in the background, and reverts itself if that throws.
/// A [GestureDetector] with `HitTestBehavior.opaque`, layered on top of the
/// card's own [InkWell] via [Positioned] rather than nested inside it, is
/// what keeps a tap here from also triggering the card's `onTap`.
class _FavoriteHeartButton extends StatefulWidget {
  const _FavoriteHeartButton({
    required this.isSaved,
    this.onToggleSaved,
    this.size = 32,
  });

  final bool isSaved;
  final Future<void> Function(bool saved)? onToggleSaved;
  final double size;

  @override
  State<_FavoriteHeartButton> createState() => _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends State<_FavoriteHeartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scale;
  late bool _saved;

  @override
  void initState() {
    super.initState();
    _saved = widget.isSaved;
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.35).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.35, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 65,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(_FavoriteHeartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSaved != oldWidget.isSaved) {
      setState(() => _saved = widget.isSaved);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    _controller.forward(from: 0);
    final next = !_saved;
    setState(() => _saved = next);

    final callback = widget.onToggleSaved;
    if (callback == null) return;
    try {
      await callback(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saved = !next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar favoritos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
          child: Icon(
            _saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: _saved ? _kAccent : Colors.white70,
            size: widget.size * 0.55,
          ),
        ),
      ),
    );
  }
}

/// Horizontal service card — cover photo, verified badge, name, category
/// pill, rating, owner's city, price, and a favorite heart. Used by
/// `ClientHomeScreen`'s "Todos los actos" list and `SavedServicesScreen`'s
/// favorites list, so both read as the same visual language instead of two
/// hand-maintained copies drifting apart.
class ServiceListCard extends StatelessWidget {
  const ServiceListCard({
    super.key,
    required this.service,
    this.onTap,
    this.isSaved = false,
    this.onToggleSaved,
  });

  final ProviderService service;
  final VoidCallback? onTap;

  /// Whether this service is already in the client's favorites — seeded
  /// from whatever fetched the list (e.g.
  /// `ClientRepository.fetchSavedServices`), not looked up by this widget.
  final bool isSaved;

  /// Called with the new desired saved state right after the heart is
  /// tapped; the heart already updated optimistically by the time this
  /// runs, and reverts itself if the returned future throws. `null` hides
  /// nothing — the heart still renders — it just becomes a no-op tap.
  final Future<void> Function(bool saved)? onToggleSaved;

  @override
  Widget build(BuildContext context) {
    final location = service.ownerCity?.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ServiceCoverImage(
                        url: service.coverPhotoUrl,
                        width: 76,
                        height: 76,
                      ),
                    ),
                    if (service.isVerified)
                      const Positioned(top: 4, left: 4, child: ServiceVerifiedBadge(size: 16)),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: _FavoriteHeartButton(
                        isSaved: isSaved,
                        onToggleSaved: onToggleSaved,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ServiceGenrePill(text: service.category.toUpperCase()),
                      const SizedBox(height: 6),
                      ServiceRatingRow(
                        rating: service.rating,
                        reviewsCount: service.reviewsCount,
                        color: _kTextSecondary,
                      ),
                      if (location != null && location.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on, size: 13, color: _kTextSecondary),
                            const SizedBox(width: 3),
                            Text(
                              location,
                              style: const TextStyle(color: _kTextSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (service.pricePerHour != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      formatCopPrice(service.pricePerHour!),
                      style: const TextStyle(color: _kAccent, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
