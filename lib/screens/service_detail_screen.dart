import 'package:flutter/material.dart';

import '../core/utils/currency.dart';
import '../models/provider_service.dart';
import 'widgets/services/service_cover_image.dart';
import 'widgets/services/service_list_card.dart';

const _kBackground = Color(0xFF0D0D12);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

/// Placeholder detail screen for a `provider_services` row — reached by
/// tapping any [ServiceListCard]/featured card. Takes the full
/// [ProviderService] the caller already fetched (its `.id` is the "ID del
/// servicio" this screen is addressed by) instead of re-querying by id,
/// since a redundant round trip for data already in hand would be pure
/// waste. Booking/reviews/gallery are intentionally not built yet — this
/// is the "archivo base" the task asked for, not the full detail flow.
class ServiceDetailScreen extends StatelessWidget {
  const ServiceDetailScreen({super.key, required this.service});

  final ProviderService service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: _kBackground,
        elevation: 0,
        title: Text(service.businessName, style: const TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ServiceCoverImage(
                url: service.coverPhotoUrl,
                width: double.infinity,
                height: 220,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    service.businessName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (service.pricePerHour != null)
                  Text(
                    formatCopPrice(service.pricePerHour!),
                    style: const TextStyle(
                      color: _kAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ServiceGenrePill(text: service.category.toUpperCase()),
            const SizedBox(height: 20),
            Text(
              service.description.isEmpty ? 'Sin descripción.' : service.description,
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, color: _kAccent, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${service.rating.toStringAsFixed(1)} (${service.reviewsCount} reseñas)',
                  style: const TextStyle(color: _kTextSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
