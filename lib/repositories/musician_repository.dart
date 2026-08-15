import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/musician.dart';
import '../models/musician_photo.dart';
import '../models/musician_stats.dart';

const String _photosBucket = 'musician-photos';

/// Every read/write the app performs against the `profiles` and
/// `contact_events` tables goes through here — UI widgets never touch the
/// Supabase SDK directly.
class MusicianRepository {
  MusicianRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Directory query with dynamic filters, applied server-side so the
  /// result set (and the "N músicos" count derived from it) always reflects
  /// exactly what matched.
  ///
  /// A non-empty [search] routes through the `search_musicians` SQL function,
  /// which matches the term against name, base city, coverage cities,
  /// instruments, genres and services all at once — PostgREST still lets the
  /// other filters and the ordering below chain on top of the function's
  /// result set, exactly as if it were a plain `select()`.
  ///
  /// Geographic scoping (requirement 4): by default this only returns
  /// musicians near [nearCity] — their base [Musician.city] matches it, or
  /// it's one of their [Musician.coverageCities] (they travel there). Set
  /// [searchNationwide] to `true` (the dashboard's "Toda Colombia" switch)
  /// to drop that filter and search the whole country.
  Future<List<Musician>> fetchMusicians({
    String? instrument,
    String? genre,
    String? service,
    bool? onlyFree,
    String? search,
    String? nearCity,
    bool searchNationwide = false,
  }) async {
    final term = search?.trim();
    PostgrestFilterBuilder<PostgrestList> query =
        (term != null && term.isNotEmpty)
        ? _client.rpc<PostgrestList>(
            'search_musicians',
            params: {'search_term': term},
          )
        : _client.from('profiles').select();

    if (instrument != null && instrument.isNotEmpty) {
      query = query.contains('instruments', [instrument]);
    }
    if (genre != null && genre.isNotEmpty) {
      query = query.contains('genres', [genre]);
    }
    if (service != null && service.isNotEmpty) {
      query = query.contains('services', [service]);
    }
    if (onlyFree == true) {
      query = query.eq('is_free', true);
    }

    final city = nearCity?.trim();
    if (!searchNationwide && city != null && city.isNotEmpty) {
      // PostgREST `.or()` syntax: an inline comma-separated list of
      // `column.operator.value` clauses, OR-ed together. `cs` (contains)
      // needs the value as a Postgres array literal — `{"City"}` — quoted
      // so city names with spaces (e.g. "Santa Marta") parse as one element.
      query = query.or('city.eq.$city,coverage_cities.cs.{"$city"}');
    }

    final rows = await query
        .order('is_free', ascending: false)
        .order('rating', ascending: false);

    return rows.map(Musician.fromJson).toList();
  }

  /// The profile of the currently authenticated musician, used for the
  /// dashboard greeting and to prefill "Mi Estado".
  Future<Musician?> fetchCurrentProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;

    final row = await _client
        .from('profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();
    if (row == null) return null;
    return Musician.fromJson(row);
  }

  /// Atomically updates the logged-in musician's availability: the
  /// Libre/Ocupado switch, their current "ocupado" time window, and either
  /// the status message shown on the dashboard card or the free-text
  /// [availabilityNote] describing their usual schedule while free.
  /// [busyUntil] is the absolute moment the dashboard's auto check-out
  /// assistant should treat this "ocupado" window as expired — pass `null`
  /// when marking free or when no limit applies. RLS guarantees a musician
  /// can only ever touch their own row.
  Future<void> updateMusicianStatus({
    required bool isFree,
    required String statusMessage,
    required String availableFrom,
    required String availableTo,
    required String availabilityNote,
    DateTime? busyUntil,
  }) async {
    final uid = _requireUserId();
    await _client
        .from('profiles')
        .update({
          'is_free': isFree,
          'status_message': statusMessage,
          'available_from': availableFrom,
          'available_to': availableTo,
          'availability_note': availabilityNote,
          'busy_until': busyUntil?.toUtc().toIso8601String(),
        })
        .eq('id', uid);
  }

  /// Updates the logged-in musician's public profile info: name, city,
  /// contact phone, coverage cities, the [services] they offer, the
  /// [instruments]/[genres] they perform (when offering the "Músico"
  /// service) and/or their [serviceDescription] inventory (when offering a
  /// technical service). Separate from [updateMusicianStatus] since these
  /// fields describe who the musician is rather than their availability
  /// right now. RLS guarantees a musician can only ever touch their own row.
  Future<void> updateMusicianProfile({
    required String fullName,
    required List<String> instruments,
    required String city,
    required String phone,
    required List<String> genres,
    required List<String> services,
    required String serviceDescription,
    required List<String> coverageCities,
  }) async {
    final uid = _requireUserId();
    await _client
        .from('profiles')
        .update({
          'full_name': fullName,
          'instruments': instruments,
          'city': city,
          'phone': phone,
          'genres': genres,
          'services': services,
          'service_description': serviceDescription,
          'coverage_cities': coverageCities,
        })
        .eq('id', uid);
  }

  /// Confirms the auto check-out prompt: the musician's gig ended, so they
  /// go back to free and the scheduled cutoff is cleared.
  Future<void> markAsFree() async {
    final uid = _requireUserId();
    await _client
        .from('profiles')
        .update({'is_free': true, 'busy_until': null})
        .eq('id', uid);
  }

  /// Dismisses the auto check-out prompt with "sigo ocupado": pushes
  /// `busy_until` forward by [extra] so the prompt doesn't re-fire right away.
  Future<void> snoozeBusyUntil(Duration extra) async {
    final uid = _requireUserId();
    final newBusyUntil = DateTime.now().add(extra);
    await _client
        .from('profiles')
        .update({'busy_until': newBusyUntil.toUtc().toIso8601String()})
        .eq('id', uid);
  }

  /// Live count of musicians currently marked as free, for the dashboard's
  /// real-time header counter. Backed by a Postgres changes subscription,
  /// so it updates the instant any musician flips their switch.
  Stream<int> streamAvailableCount() {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .map((rows) => rows.where((row) => row['is_free'] == true).length);
  }

  /// Contact counters for the "Mi Estado" stats panel.
  Future<MusicianStats> fetchContactStats(String musicianId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfMonth = DateTime(now.year, now.month, 1);

    final todayRows = await _client
        .from('contact_events')
        .select('id')
        .eq('musician_id', musicianId)
        .gte('created_at', startOfDay.toIso8601String());

    final monthRows = await _client
        .from('contact_events')
        .select('id')
        .eq('musician_id', musicianId)
        .gte('created_at', startOfMonth.toIso8601String());

    return MusicianStats(
      contactsToday: todayRows.length,
      contactsThisMonth: monthRows.length,
    );
  }

  /// Logs a WhatsApp/call tap so it feeds into [fetchContactStats] for the
  /// contacted musician.
  Future<void> logContactEvent({
    required String musicianId,
    required String contactType,
  }) async {
    await _client.from('contact_events').insert({
      'musician_id': musicianId,
      'contact_type': contactType,
    });
  }

  /// A musician's live-performance photo portfolio, newest first.
  Future<List<MusicianPhoto>> fetchPhotos(String musicianId) async {
    final rows = await _client
        .from('musician_photos')
        .select()
        .eq('musician_id', musicianId)
        .order('created_at', ascending: false);
    return rows.map(MusicianPhoto.fromJson).toList();
  }

  /// Uploads [bytes] to the `musician-photos` bucket under the logged-in
  /// musician's own folder (storage policies key off that prefix), then
  /// records the public URL in `musician_photos`.
  Future<MusicianPhoto> uploadPhoto({
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final uid = _requireUserId();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final path = '$uid/$fileName';

    await _client.storage
        .from(_photosBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    final imageUrl = _client.storage.from(_photosBucket).getPublicUrl(path);

    final row = await _client
        .from('musician_photos')
        .insert({'musician_id': uid, 'image_url': imageUrl})
        .select()
        .single();
    return MusicianPhoto.fromJson(row);
  }

  /// Removes both the storage object and its `musician_photos` row.
  Future<void> deletePhoto(MusicianPhoto photo) async {
    _requireUserId();
    const marker = '$_photosBucket/';
    final markerIndex = photo.imageUrl.indexOf(marker);
    if (markerIndex != -1) {
      final path = photo.imageUrl.substring(markerIndex + marker.length);
      await _client.storage.from(_photosBucket).remove([path]);
    }
    await _client.from('musician_photos').delete().eq('id', photo.id);
  }

  String _requireUserId() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('No hay una sesión activa.');
    }
    return uid;
  }
}
