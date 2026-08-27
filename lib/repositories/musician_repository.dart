import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/city_zones.dart';
import '../models/musician.dart';
import '../models/musician_stats.dart';
import '../models/musician_video.dart';
import '../models/profile_summary.dart';
import '../models/video_feed_item.dart';

const String _photosBucket = 'musician-photos';
const String _avatarsBucket = 'avatars';
const String _videosBucket = 'musician-videos';

/// Columns pulled for the `musician_videos` resource PostgREST embeds
/// alongside every `profiles` row — shared by [fetchMusicians] and
/// [fetchCurrentProfile] so the two selects can't drift out of sync.
const String _videoColumns =
    'id, musician_id, video_url, views_count, created_at';

/// `profiles` columns the Reels-style feed needs for its overlay/contact
/// buttons — a small subset of what [Musician.fromJson] parses, since the
/// feed never shows a full profile card.
const String _feedProfileColumns =
    'full_name, avatar_url, city, phone, is_free, instruments, genres, services';

/// Every read/write the app performs against the `profiles` and
/// `contact_events` tables goes through here — UI widgets never touch the
/// Supabase SDK directly.
class MusicianRepository {
  MusicianRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// The logged-in user's id, or `null` when signed out — used by screens to
  /// hide/guard actions (like "Seguir") against a user's own profile.
  String? get currentUserId => _client.auth.currentUser?.id;

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
  ///
  /// [nearCity] is also widened to every city in the same [CityZones]
  /// cluster before filtering, so a musician based in a commuter town (e.g.
  /// Lebrija) still shows up for a contractor searching from the anchor city
  /// (Bucaramanga) even if they never explicitly listed it in their
  /// coverage — see [CityZones] for why this is a static table instead of a
  /// geocoding API call.
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

    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId != null) {
      // Excludes the logged-in musician from their own directory feed —
      // they manage their profile via [fetchCurrentProfile]/"Mi Estado"
      // instead of finding themselves in the public listing.
      query = query.neq('id', currentUserId);
    }

    final city = nearCity?.trim();
    if (!searchNationwide && city != null && city.isNotEmpty) {
      // Dual coverage criterion, widened to the whole metro zone: match
      // either a base `city` that's IN the zone (`city.in.(...)`) or a
      // `coverage_cities` array that overlaps it at all (`coverage_cities
      // .ov.{...}`, Postgres `&&`) — either is enough to surface the
      // musician. `CityZones.expand` returns `[city]` unchanged for any
      // city outside the curated table, so this is a strict superset of the
      // previous single-city `.eq`/`.cs` filter, never a narrowing.
      final zoneCities = CityZones.expand(city);
      final cityList = zoneCities.map((c) => '"$c"').join(',');
      query = query.or('city.in.($cityList),coverage_cities.ov.{$cityList}');
    }

    // `.select()` here (after every filter is already applied) is what
    // adds the `musician_videos` embed to the response — PostgREST embeds
    // work the same way on a `setof profiles`-returning RPC as on a plain
    // table select, but the postgrest-dart type system only exposes
    // `.select()` at this transform stage, after filtering is done.
    final rows = await query
        .select('*, musician_videos($_videoColumns)')
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
        .select('*, musician_videos($_videoColumns)')
        .eq('id', uid)
        .maybeSingle();
    if (row == null) return null;
    return Musician.fromJson(row);
  }

  /// Any musician's full profile by id — used by [VideoFeedScreen] to open
  /// [MusicianDetailScreen] when the viewer taps a video's profile row
  /// (that screen needs the full [Musician], not [VideoFeedItem]'s smaller
  /// subset of columns).
  Future<Musician?> fetchMusicianById(String id) async {
    final row = await _client
        .from('profiles')
        .select('*, musician_videos($_videoColumns)')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Musician.fromJson(row);
  }

  /// Global feed for [VideoFeedScreen]: the most recent uploads across every
  /// musician, newest first, each carrying just enough of its owner's
  /// profile (via the `profiles` embed — the reverse direction of
  /// [fetchMusicians]'s `musician_videos` embed) to render the overlay and
  /// contact buttons. [before] pages backward from that video's upload
  /// time, for infinite scroll as the viewer nears the end of [_items].
  Future<List<VideoFeedItem>> fetchVideoFeed({
    int limit = 8,
    DateTime? before,
  }) async {
    PostgrestFilterBuilder<PostgrestList> query = _client
        .from('musician_videos')
        .select();

    if (before != null) {
      query = query.lt('created_at', before.toIso8601String());
    }

    final rows = await query
        .select('$_videoColumns, profiles($_feedProfileColumns)')
        .order('created_at', ascending: false)
        .limit(limit);

    return rows.map(VideoFeedItem.fromJson).toList();
  }

  /// Whether [phone] (already in `+57XXXXXXXXXX` form) is already on some
  /// *other* profile — called from [StatusScreen._save] before writing, so
  /// two musicians never end up sharing one WhatsApp contact number.
  /// `excludingId` is the logged-in musician's own id, so saving with their
  /// own unchanged number never flags itself as a duplicate.
  Future<bool> isPhoneTaken(String phone, {required String excludingId}) async {
    final rows = await _client
        .from('profiles')
        .select('id')
        .eq('phone', phone)
        .neq('id', excludingId)
        .limit(1);
    return rows.isNotEmpty;
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
    required int experienceYears,
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
          'experience_years': experienceYears,
          'phone': phone,
          'genres': genres,
          'services': services,
          'service_description': serviceDescription,
          'coverage_cities': coverageCities,
        })
        .eq('id', uid);
  }

  /// Quick optimistic toggle for the dashboard header's availability switch
  /// — flips only `is_free`. Turning it on also clears any stale
  /// `busy_until` so the auto check-out assistant doesn't immediately
  /// re-fire; turning it off leaves `busy_until` untouched (picking an exact
  /// return time is still done from "Mi Estado").
  Future<void> setAvailability(bool isFree) async {
    final uid = _requireUserId();
    await _client
        .from('profiles')
        .update({'is_free': isFree, if (isFree) 'busy_until': null})
        .eq('id', uid);
  }

  /// Confirms the auto check-out prompt: the musician's gig ended, so they
  /// go back to free and the scheduled cutoff is cleared.
  Future<void> markAsFree() => setAvailability(true);

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

  /// Contact/followers/likes counters for the "Mi Estado" header and stats
  /// panel — four independent counts fetched in parallel via [Future.wait]
  /// rather than sequentially, since none of them depend on each other.
  Future<MusicianStats> fetchContactStats(String musicianId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfMonth = DateTime(now.year, now.month, 1);

    final results = await Future.wait([
      _client
          .from('contact_events')
          .select('id')
          .eq('musician_id', musicianId)
          .gte('created_at', startOfDay.toIso8601String()),
      _client
          .from('contact_events')
          .select('id')
          .eq('musician_id', musicianId)
          .gte('created_at', startOfMonth.toIso8601String()),
      _client
          .from('musician_follows')
          .select('follower_id')
          .eq('musician_id', musicianId),
      // `!inner` makes the embedded `.eq()` actually restrict the outer
      // `video_likes` rows returned, instead of just filtering which
      // `musician_videos` fields come back per row.
      _client
          .from('video_likes')
          .select('video_id, musician_videos!inner(musician_id)')
          .eq('musician_videos.musician_id', musicianId),
    ]);

    return MusicianStats(
      contactsToday: results[0].length,
      contactsThisMonth: results[1].length,
      followersCount: results[2].length,
      totalVideoLikes: results[3].length,
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

  /// Uploads [bytes] to the `musician-photos` bucket under the logged-in
  /// musician's own folder, then appends the resulting public URL to their
  /// `profiles.photos` array via the `add_profile_photo` RPC (see
  /// `supabase/schema.sql`). That RPC does an atomic `array_append` rather
  /// than a plain `.update()` read-modify-write, which is what lets the
  /// DB-side `profiles_photos_max_10` CHECK hold even under concurrent
  /// edits from two devices — the [MediaLimits.maxPhotos] check on the UI
  /// side is only the fast, friendly rejection, not the real guardrail.
  Future<String> addPhoto({
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
    final photoUrl = _client.storage.from(_photosBucket).getPublicUrl(path);

    await _client.rpc('add_profile_photo', params: {'photo_url': photoUrl});
    return photoUrl;
  }

  /// Removes both the storage object and the URL's entry in
  /// `profiles.photos`.
  Future<void> removePhoto(String photoUrl) async {
    _requireUserId();
    const marker = '$_photosBucket/';
    final markerIndex = photoUrl.indexOf(marker);
    if (markerIndex != -1) {
      final path = photoUrl.substring(markerIndex + marker.length);
      await _client.storage.from(_photosBucket).remove([path]);
    }
    await _client.rpc('remove_profile_photo', params: {'photo_url': photoUrl});
  }

  /// Uploads [bytes] — already compressed on-device via `video_compress` by
  /// the caller — to the `musician-videos` bucket, then inserts the
  /// resulting public URL as a new `musician_videos` row. The per-musician
  /// cap ([MediaLimits.maxVideos]) is enforced by the
  /// `musician_videos_max_3` trigger, which surfaces as a thrown
  /// [PostgrestException] if the UI's own check was somehow bypassed (e.g.
  /// a race between two devices).
  Future<MusicianVideo> addVideo({
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final uid = _requireUserId();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final path = '$uid/$fileName';

    await _client.storage
        .from(_videosBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    final videoUrl = _client.storage.from(_videosBucket).getPublicUrl(path);

    final row = await _client
        .from('musician_videos')
        .insert({'musician_id': uid, 'video_url': videoUrl})
        .select()
        .single();
    return MusicianVideo.fromJson(row);
  }

  /// Removes both the storage object and its `musician_videos` row.
  Future<void> removeVideo(MusicianVideo video) async {
    _requireUserId();
    const marker = '$_videosBucket/';
    final markerIndex = video.videoUrl.indexOf(marker);
    if (markerIndex != -1) {
      final path = video.videoUrl.substring(markerIndex + marker.length);
      await _client.storage.from(_videosBucket).remove([path]);
    }
    await _client.from('musician_videos').delete().eq('id', video.id);
  }

  /// Fire-and-forget view increment for [videoId] — `increment_video_view`
  /// (see `supabase/schema.sql`) is the only path allowed to touch
  /// `views_count`, and it silently no-ops if this same viewer already
  /// counted a view for this video in the last 30 minutes. Errors are the
  /// caller's to decide whether to swallow; a missed view is never worth
  /// interrupting playback for.
  Future<void> incrementVideoView(String videoId) {
    return _client.rpc('increment_video_view', params: {'video_id': videoId});
  }

  /// Uploads [bytes] to the `avatars` bucket under a filename unique to the
  /// logged-in musician and the current moment, then stores the resulting
  /// public URL on their `profiles` row. Returns that URL so the caller can
  /// update its local state immediately without a second round-trip.
  Future<String> updateAvatar({
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final uid = _requireUserId();
    final fileName = '$uid-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final path = '$uid/$fileName';

    await _client.storage
        .from(_avatarsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final avatarUrl = _client.storage.from(_avatarsBucket).getPublicUrl(path);

    await _client
        .from('profiles')
        .update({'avatar_url': avatarUrl})
        .eq('id', uid);
    return avatarUrl;
  }

  /// Uploads [bytes] to the `avatars` bucket (same bucket as [updateAvatar],
  /// a `cover-` filename prefix instead of `{uid}-`) and stores the
  /// resulting public URL as the logged-in musician's `cover_url` — the
  /// background photo behind the avatar on [ProfileHeader].
  Future<String> updateCover({
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final uid = _requireUserId();
    final fileName = 'cover-$uid-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final path = '$uid/$fileName';

    await _client.storage
        .from(_avatarsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final coverUrl = _client.storage.from(_avatarsBucket).getPublicUrl(path);

    await _client
        .from('profiles')
        .update({'cover_url': coverUrl})
        .eq('id', uid);
    return coverUrl;
  }

  /// Permanently deletes the logged-in musician's account: their portfolio
  /// and avatar files in Storage, then the `auth.users` row itself via the
  /// `delete_own_account` Postgres function (see `supabase/schema.sql`).
  ///
  /// Storage objects live outside the database's foreign-key graph, so
  /// cascading the `profiles` row would leave them orphaned — they're
  /// removed explicitly, and *before* the auth row, while the session (and
  /// therefore each bucket's owner-only policy) is still valid. Everything
  /// else — `profiles`, `contact_events`, `musician_photos`,
  /// `musician_videos` — is cleaned up automatically by the
  /// `on delete cascade` already set up on those tables once the
  /// `auth.users` row is gone.
  Future<void> deleteAccount() async {
    final uid = _requireUserId();

    await _deleteAllUnderPrefix(_photosBucket, uid);
    await _deleteAllUnderPrefix(_avatarsBucket, uid);
    await _deleteAllUnderPrefix(_videosBucket, uid);

    // Two independent deletion paths, tried in order. `delete_own_account`
    // (Postgres RPC) is preferred — nothing to deploy beyond schema.sql —
    // but some Supabase projects lock direct `auth.users` writes down
    // tighter than a `security definer` function owned by `postgres` can
    // get around (see that function's comment in supabase/schema.sql for
    // why). When the RPC fails for any reason, fall back to the
    // `delete-account` Edge Function, which uses the Auth Admin API and so
    // always has the rights needed regardless of table-level grants.
    try {
      await _client.rpc('delete_own_account');
    } catch (rpcError) {
      try {
        await _client.functions.invoke('delete-account');
      } catch (_) {
        // Surface the original RPC failure — it's tied to the primary,
        // documented deletion path and is more actionable to debug.
        throw rpcError;
      }
    }
  }

  Future<void> _deleteAllUnderPrefix(String bucket, String uid) async {
    final objects = await _client.storage.from(bucket).list(path: uid);
    if (objects.isEmpty) return;
    final paths = objects.map((object) => '$uid/${object.name}').toList();
    await _client.storage.from(bucket).remove(paths);
  }

  /// Which of [videoIds] the current viewer already liked, for
  /// [VideoFeedScreen]'s initial heart state. Empty (not an error) when
  /// signed out or [videoIds] is empty — nothing to look up either way.
  Future<Set<String>> fetchLikedVideoIds(List<String> videoIds) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || videoIds.isEmpty) return {};
    final rows = await _client
        .from('video_likes')
        .select('video_id')
        .eq('user_id', uid)
        .inFilter('video_id', videoIds);
    return rows.map((row) => row['video_id'] as String).toSet();
  }

  /// Records a like. Ignores a duplicate-key error from double-tapping the
  /// heart before the first insert lands — the row already existing is the
  /// desired end state either way.
  Future<void> likeVideo(String videoId) async {
    final uid = _requireUserId();
    try {
      await _client.from('video_likes').insert({
        'video_id': videoId,
        'user_id': uid,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<void> unlikeVideo(String videoId) async {
    final uid = _requireUserId();
    await _client
        .from('video_likes')
        .delete()
        .eq('video_id', videoId)
        .eq('user_id', uid);
  }

  /// Which of [musicianIds] the current viewer already follows, for
  /// [VideoFeedScreen]'s initial "Seguir"/"Siguiendo" state.
  Future<Set<String>> fetchFollowedMusicianIds(List<String> musicianIds) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || musicianIds.isEmpty) return {};
    final rows = await _client
        .from('musician_follows')
        .select('musician_id')
        .eq('follower_id', uid)
        .inFilter('musician_id', musicianIds);
    return rows.map((row) => row['musician_id'] as String).toSet();
  }

  Future<void> followMusician(String musicianId) async {
    final uid = _requireUserId();
    if (uid == musicianId) return;
    try {
      await _client.from('musician_follows').insert({
        'follower_id': uid,
        'musician_id': musicianId,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  Future<void> unfollowMusician(String musicianId) async {
    final uid = _requireUserId();
    await _client
        .from('musician_follows')
        .delete()
        .eq('musician_id', musicianId)
        .eq('follower_id', uid);
  }

  /// Everyone following [musicianId], newest first — feeds the tappable
  /// "N seguidores" list on both "Mi Estado" and [MusicianDetailScreen].
  ///
  /// Goes through the `get_musician_followers` RPC (a `security definer`
  /// SQL function joining `musician_follows` to `profiles`) rather than a
  /// plain `.select()`, because the `musician_follows` RLS policy only lets
  /// a row be read by its follower or its musician — it can't be opened for
  /// an arbitrary third viewer the way this public-directory list needs.
  Future<List<ProfileSummary>> fetchFollowers(String musicianId) async {
    final rows = await _client.rpc(
      'get_musician_followers',
      params: {'target_musician_id': musicianId},
    );
    return (rows as List)
        .map((row) => ProfileSummary.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Everyone who has liked any of [musicianId]'s videos, newest like
  /// first, deduplicated per user — same `security definer` RPC pattern as
  /// [fetchFollowers], for the same reason (`video_likes` RLS is
  /// liker-only).
  Future<List<ProfileSummary>> fetchVideoLikers(String musicianId) async {
    final rows = await _client.rpc(
      'get_video_likers',
      params: {'target_musician_id': musicianId},
    );
    return (rows as List)
        .map((row) => ProfileSummary.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Counts backing [MusicianDetailScreen]'s tappable followers/likes row —
  /// reuses [fetchFollowers]/[fetchVideoLikers] rather than a separate
  /// count-only query, so the displayed number can never drift from what
  /// actually opens in the list sheet.
  Future<({int followers, int likes})> fetchPublicFollowStats(
    String musicianId,
  ) async {
    final followersFuture = fetchFollowers(musicianId);
    final likersFuture = fetchVideoLikers(musicianId);
    final followers = await followersFuture;
    final likers = await likersFuture;
    return (followers: followers.length, likes: likers.length);
  }

  String _requireUserId() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('No hay una sesión activa.');
    }
    return uid;
  }
}
