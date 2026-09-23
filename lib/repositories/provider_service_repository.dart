import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/provider_service.dart';

const String _coversBucket = 'service_covers';
const String _identityDocsBucket = 'identity_documents';

/// Every read/write against `provider_services` and its `service_covers`
/// Storage bucket goes through here — see `supabase/schema.sql` section 17
/// ("El Puente").
class ProviderServiceRepository {
  ProviderServiceRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Listings the Tarima client screen shows — only `approved` rows, an
  /// admin-reviewed subset of `provider_services` (see the RLS policy in
  /// `supabase/schema.sql` §17, which is what actually enforces this for
  /// every other caller too). Embeds just the owner's `city` (unlike
  /// [fetchPendingServices]'s fuller embed) — the client list card only
  /// ever shows a location line, never contact details.
  Future<List<ProviderService>> fetchApprovedServices() async {
    final rows = await _client
        .from('provider_services')
        .select('*, profiles(city)')
        .eq('status', 'approved')
        .order('created_at', ascending: false);
    return rows.map(ProviderService.fromJson).toList();
  }

  /// Rows waiting for admin moderation — see `admin_dashboard_screen.dart`.
  /// Only visible to a caller whose `profiles.is_admin` is true, enforced by
  /// the `provider_services_select_admin` RLS policy (`supabase/schema.sql`
  /// §18); every other caller's query just comes back empty. Embeds the
  /// owner's `profiles` row (PostgREST follows the `user_id` FK) so the
  /// admin detail view can show who's asking without a second round-trip.
  Future<List<ProviderService>> fetchPendingServices() async {
    final rows = await _client
        .from('provider_services')
        .select('*, profiles(full_name, city, phone, avatar_url)')
        .eq('status', 'pending_review')
        .order('created_at', ascending: false);
    return rows.map(ProviderService.fromJson).toList();
  }

  /// Every listing the logged-in musician/provider owns, any status
  /// (`pending_review`/`approved`/`rejected`) — the "Mis Servicios"
  /// management screen, unlike [fetchApprovedServices]/[fetchPendingServices],
  /// needs to show a provider their own rejected/in-review rows too.
  /// `provider_services_select` (`supabase/schema.sql` §17) already lets a
  /// caller see any status on their own `user_id`, so no new policy is
  /// needed for this.
  Future<List<ProviderService>> fetchMyServices() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('No hay una sesión activa.');
    }

    final rows = await _client
        .from('provider_services')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return rows.map(ProviderService.fromJson).toList();
  }

  /// Permanently removes [serviceId] — `provider_services_delete_own`
  /// (§17) already restricts this to the row's own `user_id`, so no extra
  /// ownership filter is needed here. Doesn't touch the Storage objects
  /// (`cover_photos`, `identity_doc_url`) it leaves behind; cleaning those
  /// up needs the actual Storage paths, not the public URLs stored on the
  /// row, and isn't part of what this screen asked for.
  Future<void> deleteService(String serviceId) async {
    await _client.from('provider_services').delete().eq('id', serviceId);
  }

  /// Updates the caller's own listing — `provider_services_update_own`
  /// (§17) restricts this to the row's own `user_id`. Always resets
  /// `status` to `pending_review` and clears `is_verified`: an edited
  /// listing is content an admin hasn't seen yet, so it goes back through
  /// moderation the same as a brand-new one. [coverPhotos] is left
  /// untouched (`null`) when the provider didn't pick a new photo.
  Future<void> updateService({
    required String serviceId,
    required String category,
    required String businessName,
    required String description,
    double? pricePerHour,
    required String pricingType,
    required Map<String, dynamic> details,
    required List<String> coverageAreas,
    required int advancePercentage,
    required bool priceVisible,
    required List<String> musicGenres,
    List<String>? coverPhotos,
  }) async {
    final update = <String, dynamic>{
      'category': category,
      'business_name': businessName,
      'description': description,
      'price_per_hour': pricePerHour,
      'pricing_type': pricingType,
      'details': details,
      'coverage_areas': coverageAreas,
      'advance_percentage': advancePercentage,
      'price_visible': priceVisible,
      'music_genres': musicGenres,
      'status': 'pending_review',
      'is_verified': false,
    };
    if (coverPhotos != null) update['cover_photos'] = coverPhotos;

    await _client.from('provider_services').update(update).eq('id', serviceId);
  }

  /// Approves or rejects a pending service — same RLS restriction as
  /// [fetchPendingServices] applies to the write.
  Future<void> updateServiceStatus({
    required String serviceId,
    required String newStatus,
    required bool isVerified,
  }) async {
    await _client
        .from('provider_services')
        .update({'status': newStatus, 'is_verified': isVerified})
        .eq('id', serviceId);
  }

  /// Uploads each picked [images] to `{userId}/...` in the `service_covers`
  /// bucket and returns their public URLs, same order as the input list.
  /// `readAsBytes()` + `uploadBinary` (rather than `upload(File(...))`) is
  /// what keeps this working on web, where an [XFile] has no filesystem
  /// path to hand the SDK.
  Future<List<String>> uploadCoverPhotos({
    required List<XFile> images,
    required String userId,
  }) async {
    final urls = <String>[];
    for (var i = 0; i < images.length; i++) {
      final bytes = await images[i].readAsBytes();
      final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';

      await _client.storage
          .from(_coversBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      urls.add(_client.storage.from(_coversBucket).getPublicUrl(path));
    }
    return urls;
  }

  /// Reads a signed, time-limited URL for a cédula stored under
  /// [path] (the value in `provider_services.identity_doc_url`) — the
  /// `identity_documents` bucket is private, so there is no public URL to
  /// hand back the way [uploadCoverPhotos] does. Only the document's owner
  /// or an admin can successfully call this; anyone else's request is
  /// rejected by the storage RLS policies before a URL is even generated
  /// (`supabase/schema.sql` §20).
  Future<String> getIdentityDocumentSignedUrl(
    String path, {
    int expiresInSeconds = 300,
  }) {
    return _client.storage
        .from(_identityDocsBucket)
        .createSignedUrl(path, expiresInSeconds);
  }

  /// Uploads the musician's cédula (image or PDF) to
  /// `{userId}/...` in the private `identity_documents` bucket and returns
  /// its Storage PATH — never a public URL, since none exists for this
  /// bucket. `file_picker`'s [PlatformFile.bytes] (not `.path`) is what
  /// keeps this working on web, same reasoning as [uploadCoverPhotos].
  Future<String> uploadIdentityDocument({
    required PlatformFile file,
    required String userId,
  }) async {
    final bytes = file.bytes;
    if (bytes == null) {
      throw StateError('No se pudo leer el archivo seleccionado.');
    }

    final extension = (file.extension ?? 'bin').toLowerCase();
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';

    await _client.storage
        .from(_identityDocsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _identityDocContentType(extension)),
        );

    return path;
  }

  /// Uploads a selfie captured live via the device camera — [photo] must
  /// come from `ImagePicker(source: ImageSource.camera)`, never the
  /// gallery, so the admin can trust it was taken at that moment. Goes to
  /// `{userId}/selfie_...` in the same private `identity_documents` bucket
  /// as the cédula: its RLS policies key only on the folder prefix, not
  /// the filename, so no new policy is needed for this. Returns the
  /// Storage PATH, same as [uploadIdentityDocument].
  Future<String> uploadIdentitySelfie({
    required XFile photo,
    required String userId,
  }) async {
    final bytes = await photo.readAsBytes();
    final path = '$userId/selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _client.storage
        .from(_identityDocsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );

    return path;
  }

  String _identityDocContentType(String extension) {
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      default:
        return 'image/jpeg';
    }
  }

  /// Creates the musician's commercial profile, always starting in
  /// `pending_review` — an admin approves it before it's listed on the
  /// Tarima (enforced server-side by the column default, not passed here).
  /// Routed through the `create_provider_service_with_consent` RPC rather
  /// than a plain `.insert()`, since it also writes the Habeas Data
  /// `user_consents` audit row atomically with the same call — see
  /// `supabase/schema.sql` §20 for why that pairing can't be two separate
  /// client-side inserts.
  Future<void> createService({
    required String category,
    required String businessName,
    required String description,
    double? pricePerHour,
    List<String> coverPhotos = const [],
    required String identityDocUrl,
    required String selfieUrl,
    required String pricingType,
    Map<String, dynamic> details = const {},
    List<String> coverageAreas = const [],
    required int advancePercentage,
    required bool priceVisible,
    List<String> musicGenres = const [],
  }) async {
    if (_client.auth.currentUser?.id == null) {
      throw StateError('No hay una sesión activa.');
    }

    await _client.rpc(
      'create_provider_service_with_consent',
      params: {
        'category': category,
        'business_name': businessName,
        'description': description,
        'price_per_hour': pricePerHour,
        'cover_photos': coverPhotos,
        'identity_doc_url': identityDocUrl,
        'selfie_url': selfieUrl,
        'pricing_type': pricingType,
        'details': details,
        'coverage_areas': coverageAreas,
        'advance_percentage': advancePercentage,
        'price_visible': priceVisible,
        'music_genres': musicGenres,
      },
    );
  }
}
