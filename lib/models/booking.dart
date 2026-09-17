/// A client's booking request against a `provider_services` row — see
/// `supabase/schema.sql` §22. `serviceName`/`serviceCoverUrl` come from the
/// `provider_services` embed `ClientRepository.fetchMyBookings` selects
/// alongside the row, so `MyBookingsScreen` never needs a second query per
/// card.
class Booking {
  const Booking({
    required this.id,
    required this.clientId,
    required this.serviceId,
    required this.eventDate,
    required this.status,
    required this.createdAt,
    required this.serviceName,
    this.serviceCoverUrl,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    final service = json['provider_services'] as Map<String, dynamic>?;
    final coverPhotos = (service?['cover_photos'] as List<dynamic>?)?.cast<String>();

    return Booking(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      serviceId: json['service_id'] as String,
      eventDate: DateTime.parse(json['event_date'] as String),
      status: json['status'] as String? ?? 'pending_advance',
      createdAt: DateTime.parse(json['created_at'] as String),
      serviceName: service?['business_name'] as String? ?? 'Servicio',
      serviceCoverUrl: (coverPhotos == null || coverPhotos.isEmpty) ? null : coverPhotos.first,
    );
  }

  final String id;
  final String clientId;
  final String serviceId;
  final DateTime eventDate;
  final String status;
  final DateTime createdAt;
  final String serviceName;
  final String? serviceCoverUrl;
}
