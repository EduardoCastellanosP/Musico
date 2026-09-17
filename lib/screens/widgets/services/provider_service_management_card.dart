import 'package:flutter/material.dart';

import '../../../core/utils/currency.dart';
import '../../../models/provider_service.dart';
import 'service_cover_image.dart';

const _kSurface = Color(0xFF17171D);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

/// A provider's own listing, from their side: thumbnail, name/category,
/// the status pill that actually matters to them (in review / approved /
/// verified / rejected), and a menu for "Editar"/"Eliminar". Distinct from
/// [ServiceListCard] (the client-facing browse card) — this one shows
/// moderation state a client never sees.
class ProviderServiceManagementCard extends StatelessWidget {
  const ProviderServiceManagementCard({
    super.key,
    required this.service,
    this.busy = false,
    this.onEdit,
    this.onDelete,
  });

  final ProviderService service;

  /// True while a delete for this card is in flight — disables the menu
  /// and swaps it for a small spinner instead of letting a second tap
  /// queue up behind the first.
  final bool busy;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ServiceCoverImage(url: service.coverPhotoUrl, width: 64, height: 64),
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
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  service.category,
                  style: const TextStyle(color: _kTextSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StatusPill(status: service.status, isVerified: service.isVerified),
                    if (service.pricePerHour != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        formatCopPerHour(service.pricePerHour!),
                        style: const TextStyle(color: _kAccent, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
              ),
            )
          else
            PopupMenuButton<_ManagementAction>(
              icon: const Icon(Icons.more_vert, color: _kTextSecondary),
              color: _kSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (action) {
                switch (action) {
                  case _ManagementAction.edit:
                    onEdit?.call();
                  case _ManagementAction.delete:
                    onDelete?.call();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _ManagementAction.edit,
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, color: Colors.white, size: 18),
                      SizedBox(width: 10),
                      Text('Editar', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: _ManagementAction.delete,
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                      SizedBox(width: 10),
                      Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _ManagementAction { edit, delete }

/// Maps `status`/`is_verified` to the pill a provider actually needs to
/// see. `rejected` isn't in the task brief but is a real value the
/// `status` check constraint allows (`supabase/schema.sql` §17) — leaving
/// it unhandled would silently render nothing for a rejected listing.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.isVerified});

  final String status;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'approved' when isVerified => ('Verificado', _kAccent),
      'approved' => ('Aprobado', Colors.greenAccent),
      'rejected' => ('Rechazado', Colors.redAccent),
      _ => ('En revisión', _kAccent),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
