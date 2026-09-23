import 'package:flutter/material.dart';

import '../core/utils/currency.dart';
import '../models/musician_video.dart';
import '../models/provider_service.dart';
import '../repositories/musician_repository.dart';
import 'in_app_video_player_screen.dart';
import 'widgets/services/create_service_modal.dart'
    show DetailField, kCategoryDetailFields, kMusicGenreCategories, kUniversalDetailFields;
import 'widgets/services/service_cover_image.dart';
import 'widgets/services/service_list_card.dart';

const _kBackground = Color(0xFF0D0D12);
const _kSurface = Color(0xFF17171D);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

/// Detail screen for a `provider_services` row — reached by tapping any
/// [ServiceListCard]/featured card. Takes the full [ProviderService] the
/// caller already fetched instead of re-querying by id, since a redundant
/// round trip for data already in hand would be pure waste. The bottom
/// "Reservar" button and the share icon are visual placeholders — neither
/// booking nor sharing is wired up yet.
class ServiceDetailScreen extends StatefulWidget {
  const ServiceDetailScreen({super.key, required this.service});

  final ProviderService service;

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _musicianRepository = MusicianRepository();
  late final Future<List<MusicianVideo>> _portfolioVideosFuture =
      _musicianRepository.fetchFeaturedVideos(
        musicianId: widget.service.userId,
        serviceId: widget.service.id,
      );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final hasGenres =
        kMusicGenreCategories.contains(service.category) && service.musicGenres.isNotEmpty;
    final city = service.ownerCity?.trim();

    return Scaffold(
      backgroundColor: _kBackground,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _HeroPhotoSection(service: service),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.businessName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ServiceRatingRow(rating: service.rating, reviewsCount: service.reviewsCount),
                      if (city != null && city.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        const Icon(Icons.location_on, size: 14, color: _kTextSecondary),
                        const SizedBox(width: 3),
                        Text(city, style: const TextStyle(color: _kTextSecondary, fontSize: 13)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                  _PriceAndHighlightsRow(service: service),
                  const SizedBox(height: 20),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: _kAccent,
                    labelColor: _kAccent,
                    unselectedLabelColor: _kTextSecondary,
                    labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    tabs: const [
                      Tab(text: 'Acerca de'),
                      Tab(text: 'Portafolio'),
                      Tab(text: 'Reseñas'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _TabContent(
                    service: service,
                    tabIndex: _tabController.index,
                    hasGenres: hasGenres,
                    portfolioVideosFuture: _portfolioVideosFuture,
                    musicianRepository: _musicianRepository,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const _ReserveButtonBar(),
    );
  }
}

/// Cover carousel with the back/share icons and the category + verified
/// pills overlaid on top of it, exactly like the client-preview tab in
/// `AdminServiceDetailModal` — owns its own [PageController]/page index
/// since nothing outside this widget needs them.
class _HeroPhotoSection extends StatefulWidget {
  const _HeroPhotoSection({required this.service});

  final ProviderService service;

  @override
  State<_HeroPhotoSection> createState() => _HeroPhotoSectionState();
}

class _HeroPhotoSectionState extends State<_HeroPhotoSection> {
  final _pageController = PageController();
  int _photoIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;

    return Stack(
      children: [
        ServicePhotoGallery(
          photos: service.coverPhotos,
          pageController: _pageController,
          currentIndex: _photoIndex,
          onPageChanged: (i) => setState(() => _photoIndex = i),
          height: 300,
        ),
        Positioned(
          top: 12,
          left: 12,
          child: _OverlayIconButton(
            icon: Icons.arrow_back,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: _OverlayIconButton(
            icon: Icons.share_outlined,
            // TODO: conectar el flujo real de compartir (deep link del
            // servicio, texto) cuando se defina — por ahora solo visual.
            onPressed: () {},
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: Row(
            children: [
              _OverlayPill(
                text: service.category,
                background: Colors.black.withValues(alpha: 0.55),
              ),
              if (service.isVerified) ...[
                const SizedBox(width: 8),
                _OverlayPill(
                  text: '✓ Verificado',
                  background: _kAccent,
                  textColor: Colors.black,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
      ),
    );
  }
}

class _OverlayPill extends StatelessWidget {
  const _OverlayPill({
    required this.text,
    required this.background,
    this.textColor = Colors.white,
  });

  final String text;
  final Color background;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// "DESDE $precio" (or "Precio a convenir") on the left, highlight chips —
/// only the ones with a real fact behind them — on the right.
class _PriceAndHighlightsRow extends StatelessWidget {
  const _PriceAndHighlightsRow({required this.service});

  final ProviderService service;

  @override
  Widget build(BuildContext context) {
    final priceValue = service.clientPriceLabel ?? 'Precio a convenir';
    final showDesdeCaption = service.priceVisible && service.pricePerHour != null;
    final highlights = <String>[
      if (service.details['includes_own_equipment'] == true) 'Equipo propio',
      if (kMusicGenreCategories.contains(service.category)) ...service.musicGenres,
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showDesdeCaption) ...[
                const Text(
                  'DESDE',
                  style: TextStyle(
                    color: _kTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              Text(
                priceValue,
                style: const TextStyle(color: _kAccent, fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        if (highlights.isNotEmpty)
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [for (final highlight in highlights) ServiceGenrePill(text: highlight)],
            ),
          ),
      ],
    );
  }
}

/// Switches what shows below the tab bar — "Acerca de" carries the bulk
/// of the service info (description, género principal, condiciones de
/// reserva, detalles); "Repertorio" has no structured data behind it yet;
/// "Reseñas" reuses the same rating summary the old single-page layout
/// already showed, since there's no per-review list built yet either.
class _TabContent extends StatelessWidget {
  const _TabContent({
    required this.service,
    required this.tabIndex,
    required this.hasGenres,
    required this.portfolioVideosFuture,
    required this.musicianRepository,
  });

  final ProviderService service;
  final int tabIndex;
  final bool hasGenres;
  final Future<List<MusicianVideo>> portfolioVideosFuture;
  final MusicianRepository musicianRepository;

  @override
  Widget build(BuildContext context) {
    switch (tabIndex) {
      case 1:
        return _PortfolioTab(
          videosFuture: portfolioVideosFuture,
          musicianRepository: musicianRepository,
        );
      case 2:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.star_rounded, color: _kAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                '${service.rating.toStringAsFixed(1)} (${service.reviewsCount} reseñas)',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      default:
        return _AboutTabContent(service: service, hasGenres: hasGenres);
    }
  }
}

/// Grid of the provider's videos marked `show_in_profile` — see
/// `supabase/schema.sql` §30. Tapping one opens the shared
/// [InAppVideoPlayerScreen] (same player `MusicianDetailScreen` uses),
/// counting a view the same way. Photos aren't gated by this same
/// visibility flag — the provider curates those by choosing what to
/// upload to begin with, capped at 10.
class _PortfolioTab extends StatelessWidget {
  const _PortfolioTab({required this.videosFuture, required this.musicianRepository});

  final Future<List<MusicianVideo>> videosFuture;
  final MusicianRepository musicianRepository;

  void _openVideo(BuildContext context, MusicianVideo video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InAppVideoPlayerScreen(
          videoUrl: video.videoUrl,
          onViewed: () => musicianRepository.incrementVideoView(video.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MusicianVideo>>(
      future: videosFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator(color: _kAccent)),
          );
        }
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No pudimos cargar el portafolio.',
                style: TextStyle(color: _kTextSecondary),
              ),
            ),
          );
        }

        final videos = snapshot.data ?? const [];
        if (videos.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Este proveedor aún no ha agregado videos a su portafolio.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _kTextSecondary, fontSize: 14),
              ),
            ),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: videos.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final video = videos[index];
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _PortfolioVideoTile(
                video: video,
                onTap: () => _openVideo(context, video),
              ),
            );
          },
        );
      },
    );
  }
}

/// A real thumbnail (`video.thumbnailUrl`, generated at upload time — see
/// `VideoOptimizer.generateThumbnail`) with the play icon overlaid, never
/// a flat black box: the placeholder only ever shows for the rare video
/// uploaded before that column existed, or a failed image load.
class _PortfolioVideoTile extends StatelessWidget {
  const _PortfolioVideoTile({required this.video, required this.onTap});

  final MusicianVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumbnail = video.thumbnailUrl;

    return InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumbnail != null)
            Image.network(
              thumbnail,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const _PortfolioVideoPlaceholder(),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const _PortfolioVideoPlaceholder(loading: true);
              },
            )
          else
            const _PortfolioVideoPlaceholder(),
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortfolioVideoPlaceholder extends StatelessWidget {
  const _PortfolioVideoPlaceholder({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kSurface,
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
            )
          : const Icon(Icons.smart_display_outlined, color: _kTextSecondary, size: 28),
    );
  }
}

class _AboutTabContent extends StatelessWidget {
  const _AboutTabContent({required this.service, required this.hasGenres});

  final ProviderService service;
  final bool hasGenres;

  @override
  Widget build(BuildContext context) {
    final detailRows = _detailRowsFor(service);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          service.description.isEmpty ? 'Sin descripción.' : service.description,
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        if (hasGenres) ...[
          const SizedBox(height: 20),
          _MusicGenreCard(genres: service.musicGenres),
        ],
        const SizedBox(height: 20),
        _BookingConditionsCard(service: service),
        if (detailRows.isNotEmpty) ...[
          const SizedBox(height: 20),
          _DetailsCard(rows: detailRows),
        ],
      ],
    );
  }
}

class _MusicGenreCard extends StatelessWidget {
  const _MusicGenreCard({required this.genres});

  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            genres.length > 1 ? 'GÉNEROS' : 'GÉNERO PRINCIPAL',
            style: const TextStyle(
              color: _kTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            genres.join(' / '),
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// "What it costs to book this" — price, the deposit (Sistema Anti-Fuga)
/// required to secure the booking, and the minimum lead time to reserve.
/// The deposit amount is computed here from `pricePerHour *
/// advancePercentage`, never read off a stored column — see
/// `advanceAmountFor` in `core/utils/currency.dart`, the same formula the
/// real advance-payment flow (not built yet) is meant to reuse.
class _BookingConditionsCard extends StatelessWidget {
  const _BookingConditionsCard({required this.service});

  final ProviderService service;

  @override
  Widget build(BuildContext context) {
    final price = service.pricePerHour;
    final minAdvanceNotice = service.details['min_advance_notice'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Condiciones de reserva',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ConditionRow(
            icon: Icons.sell_outlined,
            label: 'Precio',
            value: service.clientPriceLabel ?? 'No especificado',
          ),
          _ConditionRow(
            icon: Icons.shield_outlined,
            label: 'Anticipo para reservar',
            value: !service.priceVisible
                ? 'El anticipo se define al recibir tu propuesta'
                : (price != null
                    ? formatCopPrice(advanceAmountFor(price, service.advancePercentage))
                    : 'No especificado'),
          ),
          _ConditionRow(
            icon: Icons.schedule_outlined,
            label: 'Anticipación mínima',
            value: (minAdvanceNotice == null || minAdvanceNotice.trim().isEmpty)
                ? 'No especificada'
                : minAdvanceNotice,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        children: [
          Icon(icon, color: _kAccent, size: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 13)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Renders whatever category-specific + universal keys are actually
/// present in `service.details` (jsonb), with the same friendly labels
/// `CreateServiceModal` used to collect them — see `supabase/schema.sql`
/// §25. Booleans render as a check/cross line; text values as a "label:
/// value" line. Absent keys (a provider left that field blank) just don't
/// show up, rather than a label with an empty value.
List<Widget> _detailRowsFor(ProviderService service) {
  final fields = [
    ...(kCategoryDetailFields[service.category] ?? const []),
    ...kUniversalDetailFields,
  ];
  final rows = <Widget>[];
  for (final field in fields) {
    final value = service.details[field.key];
    if (value == null) continue;
    if (value is String && value.trim().isEmpty) continue;

    rows.add(_DetailRow(field: field, value: value));
  }
  return rows;
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detalles',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.field, required this.value});

  final DetailField field;
  final Object value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (field.isBoolean)
            Icon(
              value == true ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: value == true ? _kAccent : _kTextSecondary,
              size: 16,
            )
          else
            const Icon(Icons.circle, color: _kAccent, size: 6),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              field.isBoolean ? field.label : '${field.label}: $value',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed "Reservar" CTA, always visible regardless of scroll position —
/// `Scaffold.bottomNavigationBar` sits outside the scrollable body, so no
/// manual `Positioned`/`Stack` plumbing is needed for that. Not wired to
/// any real booking flow yet.
class _ReserveButtonBar extends StatelessWidget {
  const _ReserveButtonBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBackground,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              // TODO: conectar con el flujo real de reserva cuando exista.
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Reservar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}
