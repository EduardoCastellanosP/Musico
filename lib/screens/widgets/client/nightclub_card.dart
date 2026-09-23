import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/provider_service.dart';
import '../services/service_cover_image.dart';
import '../services/service_list_card.dart';

const _kBackground = Color(0xFF0D0D12);
const _kAccent = Color(0xFFFFB703);

/// Immersive card for `provider_services.category == 'Discoteca'` — taller
/// and photo-forward (fixed 240 height) compared to [ServiceListCard]'s
/// compact horizontal row, with a direct "Ver mapa" shortcut into Google
/// Maps. See `ClientHomeScreen`'s "Ocio & Discotecas" filter for where
/// this replaces [ServiceListCard] in the list.
class NightclubCard extends StatefulWidget {
  const NightclubCard({
    super.key,
    required this.service,
    required this.locationQuery,
    this.onTap,
  });

  final ProviderService service;

  /// What gets URL-encoded into the Google Maps search query — pass
  /// something like `"${service.businessName}, ${service.ownerCity}"` so
  /// the pin lands on this exact venue, not just its city.
  final String locationQuery;

  final VoidCallback? onTap;

  @override
  State<NightclubCard> createState() => _NightclubCardState();
}

class _NightclubCardState extends State<NightclubCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, value: 0, duration: const Duration(milliseconds: 400));
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _press() => _controller.animateTo(1, duration: const Duration(milliseconds: 110), curve: Curves.easeOutCubic);

  void _release() => _controller.animateTo(0, duration: const Duration(milliseconds: 420), curve: Curves.elasticOut);

  Future<void> _openMap() async {
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': widget.locationQuery,
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: GestureDetector(
        onTapDown: (_) => _press(),
        onTapUp: (_) => _release(),
        onTapCancel: _release,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 240,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: _kBackground,
                    child: ServiceCoverImage(
                      url: service.coverPhotoUrl,
                      width: double.infinity,
                      height: 240,
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black],
                        stops: [0.35, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 14,
                    child: _MapButton(onTap: _openMap),
                  ),
                  if (service.isVerified)
                    const Positioned(
                      top: 16,
                      right: 16,
                      child: Icon(Icons.verified, color: _kAccent, size: 22),
                    ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          service.businessName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ServiceGenrePill(text: service.category.toUpperCase()),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '🔥 Hoy: ${service.todaysEvent?.trim().isNotEmpty == true ? service.todaysEvent : 'Programación especial'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ),
                            if (service.clientPriceLabel != null)
                              Text(
                                'Cover: ${service.clientPriceLabel}',
                                style: const TextStyle(
                                  color: _kAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on, color: Colors.white, size: 14),
            SizedBox(width: 4),
            Text(
              'Ver mapa',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
