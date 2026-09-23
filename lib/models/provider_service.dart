import '../core/utils/currency.dart';

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
    this.pricingType = 'per_hour',
    this.details = const {},
    this.coverageAreas = const [],
    this.advancePercentage = 20,
    this.priceVisible = true,
    this.musicGenres = const [],
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
    this.selfieUrl,
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
      pricingType: json['pricing_type'] as String? ?? 'per_hour',
      details: (json['details'] as Map<String, dynamic>?) ?? const {},
      coverageAreas:
          (json['coverage_areas'] as List<dynamic>?)?.cast<String>() ?? const [],
      advancePercentage: (json['advance_percentage'] as num?)?.toInt() ?? 20,
      priceVisible: json['price_visible'] as bool? ?? true,
      musicGenres:
          (json['music_genres'] as List<dynamic>?)?.cast<String>() ?? const [],
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
      selfieUrl: json['selfie_url'] as String?,
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

  /// How [pricePerHour] should be read: `per_hour`, `fixed` (package/event
  /// rate) or `per_night`. Suggested by category in `CreateServiceModal`,
  /// editable by the provider — see `supabase/schema.sql` §25.
  final String pricingType;

  /// Optional category-specific attributes (set duration, capacity, menu
  /// type...) — free-form keys, no fixed schema. See the
  /// `_kCategoryDetailFields` mapping in `create_service_modal.dart` for
  /// which keys a given `category` actually populates.
  final Map<String, dynamic> details;

  /// Cities/municipalities this listing covers beyond the provider's own
  /// `profiles.city` — its own indexable `text[]` column (GIN), not part
  /// of [details], since the point is letting a client in one city find a
  /// provider based elsewhere. See `supabase/schema.sql` §26.
  final List<String> coverageAreas;

  /// Percentage of [pricePerHour] the client must pay as a deposit to
  /// secure a booking (Sistema Anti-Fuga) — one of 10/20/30/40/50, set by
  /// the provider at creation. The peso AMOUNT is never stored; compute it
  /// with `advanceAmountFor` in `lib/core/utils/currency.dart` so it never
  /// drifts from the current price. See `supabase/schema.sql` §27.
  final int advancePercentage;

  /// Whether [pricePerHour] is shown to clients — `false` means "Precio a
  /// convenir" everywhere client-facing (Tarima cards, detail screen,
  /// "Condiciones de reserva"), while the number itself keeps being
  /// required/stored and used internally (the provider's own advance
  /// preview, counterproposals). See `supabase/schema.sql` §28 and
  /// [clientPriceLabel].
  final bool priceVisible;

  /// Musical genres this listing plays (Vallenato, Salsa, ...) — only
  /// meaningful for `category` in ('Solista', 'DJ', 'Agrupación'). Its own
  /// indexable `text[]` column (GIN), not part of [details], for the same
  /// filtering reason as [coverageAreas]. See `supabase/schema.sql` §29.
  final List<String> musicGenres;

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

  /// Private Storage path (same private `identity_documents` bucket as
  /// [identityDocUrl], different filename prefix) for the live selfie
  /// taken at creation time — resolve to a viewable link the same way,
  /// via [ProviderServiceRepository.getIdentityDocumentSignedUrl]. Used by
  /// admin moderation to visually compare against the cédula photo.
  final String? selfieUrl;

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

  /// What every client-facing price display should render — `null` means
  /// "show nothing" (no price set, same as before `price_visible`
  /// existed), `'Precio a convenir'` when the provider explicitly hid it
  /// regardless of whether a price is set, or the formatted amount
  /// otherwise. Never used for the provider's own preview (the advance
  /// calculator in `CreateServiceModal` always shows the real number).
  String? get clientPriceLabel {
    if (!priceVisible) return 'Precio a convenir';
    final price = pricePerHour;
    return price == null ? null : formatCopPriceForPricingType(price, pricingType);
  }
}
