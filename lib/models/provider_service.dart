/// Domain model for a row in the Supabase `provider_services` table — a
/// musician's commercial "Tarima" listing (agrupación, solista, sonido...),
/// as opposed to their social `profiles` row. See `supabase/schema.sql`
/// section 17.
class ProviderService {
  const ProviderService({
    required this.id,
    required this.userId,
    required this.category,
    required this.businessName,
    required this.description,
    required this.pricePerHour,
    required this.status,
    required this.coverPhotos,
    required this.createdAt,
    this.isVerified = false,
    this.rating = 5.0,
    this.reviewsCount = 0,
    this.ownerFullName,
    this.ownerCity,
    this.ownerPhone,
    this.ownerAvatarUrl,
    this.identityDocUrl,
    this.habeasDataAcceptedAt,
    this.todaysEvent,
  });

  factory ProviderService.fromJson(Map<String, dynamic> json) {
    // PostgREST embed (`profiles(...)`) used by
    // `ProviderServiceRepository.fetchPendingServices` for the admin detail
    // view — absent from plain `provider_services` selects (e.g.
    // `fetchApprovedServices`), where every owner* field stays null.
    final owner = json['profiles'] as Map<String, dynamic>?;

    return ProviderService(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      category: json['category'] as String,
      businessName: json['business_name'] as String,
      description: json['description'] as String? ?? '',
      pricePerHour: (json['price_per_hour'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'pending_review',
      coverPhotos:
          (json['cover_photos'] as List<dynamic>?)?.cast<String>() ?? const [],
      createdAt: DateTime.parse(json['created_at'] as String),
      isVerified: json['is_verified'] as bool? ?? false,
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      reviewsCount: (json['reviews_count'] as num?)?.toInt() ?? 0,
      ownerFullName: owner?['full_name'] as String?,
      ownerCity: owner?['city'] as String?,
      ownerPhone: owner?['phone'] as String?,
      ownerAvatarUrl: owner?['avatar_url'] as String?,
      identityDocUrl: json['identity_doc_url'] as String?,
      habeasDataAcceptedAt: json['habeas_data_accepted_at'] == null
          ? null
          : DateTime.parse(json['habeas_data_accepted_at'] as String),
      todaysEvent: json['todays_event'] as String?,
    );
  }

  final String id;
  final String userId;
  final String category;
  final String businessName;
  final String description;
  final double? pricePerHour;
  final String status;
  final List<String> coverPhotos;
  final DateTime createdAt;
  final bool isVerified;
  final double rating;
  final int reviewsCount;
  final String? ownerFullName;
  final String? ownerCity;
  final String? ownerPhone;
  final String? ownerAvatarUrl;

  /// Private Storage path (not a public URL — the `identity_documents`
  /// bucket has none) for the cédula uploaded at creation time. Resolve to
  /// a viewable link via
  /// [ProviderServiceRepository.getIdentityDocumentSignedUrl].
  final String? identityDocUrl;

  /// When the musician accepted the Habeas Data authorization for this
  /// specific listing — see `supabase/schema.sql` §20 and the
  /// `user_consents` audit row written alongside it.
  final DateTime? habeasDataAcceptedAt;

  /// "What's on tonight" free text — only meaningful when `category ==
  /// 'Discoteca'`; null for every other category and for discotecas that
  /// haven't set one yet. Shown by `NightclubCard`.
  final String? todaysEvent;

  /// First cover photo, used as the card background — `null` when the
  /// listing has none yet, in which case the UI falls back to a
  /// placeholder rather than handing `Image.network` an empty string.
  String? get coverPhotoUrl => coverPhotos.isEmpty ? null : coverPhotos.first;
}
