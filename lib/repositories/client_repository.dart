import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/booking.dart';
import '../models/provider_service.dart';

/// Every read/write behind a client's "Artistas Guardados" and "Mis
/// Reservas" screens goes through here — see `supabase/schema.sql` §22.
/// Distinct from [ProviderServiceRepository], which owns the
/// musician/admin side of `provider_services` (creation, moderation).
class ClientRepository {
  ClientRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// [clientId]'s favorited listings, newest-saved first. Returns
  /// [ProviderService] directly (via the `saved_services ->
  /// provider_services -> profiles` nested embed) so `SavedServicesScreen`
  /// can reuse the exact same `ServiceListCard` the Tarima list already
  /// uses, instead of a second, saved-services-only card widget.
  Future<List<ProviderService>> fetchSavedServices(String clientId) async {
    final rows = await _client
        .from('saved_services')
        .select('provider_services(*, profiles(city))')
        .eq('client_id', clientId)
        .order('created_at', ascending: false);

    return rows
        .map((row) => row['provider_services'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map(ProviderService.fromJson)
        .toList();
  }

  /// Adds [serviceId] to the logged-in client's favorites. Ready for the
  /// service detail view's "guardar" button — nothing calls this yet.
  Future<void> saveService(String serviceId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('No hay una sesión activa.');
    await _client.from('saved_services').insert({
      'client_id': uid,
      'service_id': serviceId,
    });
  }

  /// Removes [serviceId] from favorites — used today by
  /// `SavedServicesScreen`'s swipe-to-delete.
  Future<void> unsaveService(String serviceId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('No hay una sesión activa.');
    await _client
        .from('saved_services')
        .delete()
        .eq('client_id', uid)
        .eq('service_id', serviceId);
  }

  /// [clientId]'s booking requests, soonest event first.
  Future<List<Booking>> fetchMyBookings(String clientId) async {
    final rows = await _client
        .from('bookings')
        .select('*, provider_services(business_name, cover_photos)')
        .eq('client_id', clientId)
        .order('event_date', ascending: false);
    return rows.map(Booking.fromJson).toList();
  }

  /// Creates a booking request for [serviceId], starting at
  /// `pending_advance`. Ready for the service detail view's "Reservar"
  /// button — nothing calls this yet.
  Future<void> createBooking({
    required String serviceId,
    required DateTime eventDate,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('No hay una sesión activa.');
    await _client.from('bookings').insert({
      'client_id': uid,
      'service_id': serviceId,
      'event_date': eventDate.toUtc().toIso8601String(),
    });
  }
}
