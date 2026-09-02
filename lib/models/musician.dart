import '../core/constants/media_limits.dart';
import '../core/constants/services.dart';
import 'musician_video.dart';

/// Domain model for a row in the Supabase `profiles` table.
///
/// Every field here is sourced live from the database — there is no
/// hardcoded musician data anywhere in the app. Time-of-day columns are
/// stored as 24h "HH:mm" strings so they sort/compare cleanly in SQL; the
/// 12h-formatted getters below exist purely for display.
class Musician {
  const Musician({
    required this.id,
    required this.fullName,
    required this.instruments,
    required this.city,
    required this.experienceYears,
    required this.rating,
    required this.reviewsCount,
    required this.isFree,
    required this.statusMessage,
    required this.availableFrom,
    required this.availableTo,
    required this.phone,
    required this.avatarUrl,
    required this.coverUrl,
    required this.genres,
    required this.services,
    required this.serviceDescription,
    required this.availabilityNote,
    required this.coverageCities,
    required this.busyUntil,
    required this.photos,
    required this.videos,
    required this.lastMediaAt,
    required this.isComplete,
  });

  factory Musician.fromJson(Map<String, dynamic> json) {
    return Musician(
      id: json['id'] as String,
      fullName: (json['full_name'] as String?)?.trim().isNotEmpty == true
          ? json['full_name'] as String
          : 'Músico sin nombre',
      instruments: _stringList(json['instruments']),
      city: json['city'] as String? ?? '',
      experienceYears: (json['experience_years'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewsCount: (json['reviews_count'] as num?)?.toInt() ?? 0,
      isFree: json['is_free'] as bool? ?? false,
      statusMessage: json['status_message'] as String? ?? '',
      availableFrom: json['available_from'] as String? ?? '08:00',
      availableTo: json['available_to'] as String? ?? '22:00',
      phone: json['phone'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      coverUrl: json['cover_url'] as String?,
      genres: _stringList(json['genres']),
      services: _stringList(json['services']),
      serviceDescription: json['service_description'] as String? ?? '',
      availabilityNote: json['availability_note'] as String? ?? '',
      coverageCities: _stringList(json['coverage_cities']),
      busyUntil: json['busy_until'] != null
          ? DateTime.tryParse(json['busy_until'] as String)
          : null,
      photos: _stringList(json['photos']),
      videos: _videoList(json['musician_videos']),
      lastMediaAt: json['last_media_at'] != null
          ? DateTime.tryParse(json['last_media_at'] as String)
          : null,
      isComplete: json['is_complete'] as bool? ?? false,
    );
  }

  static List<String> _stringList(dynamic value) =>
      (value as List<dynamic>?)?.map((item) => item as String).toList() ??
      const [];

  /// Parses the `musician_videos` resource PostgREST embeds alongside each
  /// `profiles` row (see `MusicianRepository`'s `select('*, musician_videos(...))')`
  /// calls), oldest first — trivial to sort client-side given the cap of 3.
  static List<MusicianVideo> _videoList(dynamic value) {
    final videos =
        (value as List<dynamic>?)
            ?.map(
              (item) => MusicianVideo.fromJson(item as Map<String, dynamic>),
            )
            .toList() ??
        <MusicianVideo>[];
    videos.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return videos;
  }

  final String id;
  final String fullName;

  /// Instruments this musician plays. Empty when they only offer a
  /// technical [services] (sound, rehearsal space, etc.).
  final List<String> instruments;

  final String city;
  final int experienceYears;
  final double rating;
  final int reviewsCount;
  final bool isFree;
  final String statusMessage;

  /// 24h "HH:mm", e.g. "22:00". Only meaningful while [isFree] is false —
  /// this is the exact start/end of the current "ocupado" window.
  final String availableFrom;

  /// 24h "HH:mm", e.g. "06:00".
  final String availableTo;

  final String phone;
  final String? avatarUrl;

  /// Public header/background photo shown behind the avatar on
  /// [MusicianDetailScreen]/[ProfileHeader]. Null falls back to a themed
  /// gradient placeholder — most musicians won't set one explicitly.
  final String? coverUrl;

  /// Musical genres this musician performs. Empty when they only offer a
  /// technical [services].
  final List<String> genres;

  /// Services offered — e.g. "Músico", "Sonido", "Ensayaderos". A profile can
  /// offer more than one at once.
  final List<String> services;

  /// Free-text inventory/description for technical services (sound gear,
  /// rehearsal space capacity, etc.). Empty when no technical service is
  /// selected.
  final String serviceDescription;

  /// Free-text usual availability window described while [isFree] is true,
  /// e.g. "Fines de semana en la noche". Distinct from [availableFrom]/
  /// [availableTo], which only apply to the current "ocupado" window.
  final String availabilityNote;

  /// Extra municipalities the musician travels to, beyond their base [city].
  final List<String> coverageCities;

  /// Scheduled end of the current "ocupado" window, used by the dashboard's
  /// auto check-out assistant. Null while free or when no limit was set.
  final DateTime? busyUntil;

  /// Public portfolio photo URLs (`musician-photos` Storage bucket), newest
  /// first. Capped at [MediaLimits.maxPhotos] by a DB constraint.
  final List<String> photos;

  /// Video portfolio (`musician_videos` table + `musician-videos` Storage
  /// bucket), each with its own view counter. Capped at
  /// [MediaLimits.maxVideos] by a DB trigger.
  final List<MusicianVideo> videos;

  /// When the musician last uploaded a portfolio photo or video — powers
  /// the dashboard card's "story ring" (see [recentlyUploaded]). Null when
  /// they've never uploaded anything.
  final DateTime? lastMediaAt;

  /// Recalculated server-side (see `schema.sql` section 13): true once this
  /// profile has a city, phone, at least one instrument/service, at least
  /// 1 photo and at least 1 video. Read-only — [copyWith] never lets the
  /// app set it directly, since only the server can know it's current.
  final bool isComplete;

  bool get canAddMorePhotos => photos.length < MediaLimits.maxPhotos;

  /// True within 48h of the musician's last portfolio upload — the window
  /// the dashboard card highlights with a gradient ring, mirroring how
  /// WhatsApp/Instagram stories fade after a day or two.
  bool get recentlyUploaded {
    final at = lastMediaAt;
    if (at == null) return false;
    return DateTime.now().difference(at).inHours < 48;
  }

  bool get canAddMoreVideos => videos.length < MediaLimits.maxVideos;

  bool get offersMusicianService =>
      services.contains(MusicianServices.musician);

  bool get offersTechnicalService =>
      services.any(MusicianServices.technical.contains);

  /// Section title for [serviceDescription] — shared by the "Mi Estado"
  /// edit form and [MusicianDetailScreen] so both always agree on what to
  /// call this free-text field for a given role mix.
  String get descriptionSectionTitle {
    if (offersMusicianService && offersTechnicalService) {
      return 'Experiencia y equipo que ofrece';
    }
    if (offersMusicianService) return 'Experiencia';
    if (offersTechnicalService) return 'Inventario y equipo';
    return 'Descripción';
  }

  Musician copyWith({
    String? fullName,
    List<String>? instruments,
    String? city,
    int? experienceYears,
    String? phone,
    String? avatarUrl,
    String? coverUrl,
    List<String>? genres,
    List<String>? services,
    String? serviceDescription,
    String? availabilityNote,
    List<String>? coverageCities,
    bool? isFree,
    String? statusMessage,
    String? availableFrom,
    String? availableTo,
    DateTime? busyUntil,
    bool clearBusyUntil = false,
    List<String>? photos,
    List<MusicianVideo>? videos,
    DateTime? lastMediaAt,
  }) {
    return Musician(
      id: id,
      fullName: fullName ?? this.fullName,
      instruments: instruments ?? this.instruments,
      city: city ?? this.city,
      experienceYears: experienceYears ?? this.experienceYears,
      rating: rating,
      reviewsCount: reviewsCount,
      isFree: isFree ?? this.isFree,
      statusMessage: statusMessage ?? this.statusMessage,
      availableFrom: availableFrom ?? this.availableFrom,
      availableTo: availableTo ?? this.availableTo,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      genres: genres ?? this.genres,
      services: services ?? this.services,
      serviceDescription: serviceDescription ?? this.serviceDescription,
      availabilityNote: availabilityNote ?? this.availabilityNote,
      coverageCities: coverageCities ?? this.coverageCities,
      busyUntil: clearBusyUntil ? null : (busyUntil ?? this.busyUntil),
      photos: photos ?? this.photos,
      videos: videos ?? this.videos,
      lastMediaAt: lastMediaAt ?? this.lastMediaAt,
      isComplete: isComplete,
    );
  }

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  /// Only digits, suitable for `tel:` and `wa.me/` links.
  String get _digitsOnlyPhone => phone.replaceAll(RegExp(r'[^0-9]'), '');

  bool get hasPhone => _digitsOnlyPhone.isNotEmpty;

  Uri get whatsappUri => Uri.parse('https://wa.me/$_digitsOnlyPhone');

  Uri get callUri => Uri(scheme: 'tel', path: _digitsOnlyPhone);

  String get availableFrom12h => _to12h(availableFrom);

  String get availableTo12h => _to12h(availableTo);

  /// Comma-joined instruments for compact display, e.g. "Acordeonero, Cajero".
  String get instrumentsSummary => instruments.join(', ');

  /// Comma-joined genres for compact display, e.g. "Vallenato, Tropical".
  String get genresSummary => genres.join(', ');

  /// e.g. "Libre desde las 10:00 PM" when free, or the musician's own
  /// status message (falling back to their return time) when busy.
  String get availabilityLabel {
    if (isFree) {
      return availabilityNote.trim().isNotEmpty
          ? availabilityNote
          : 'Disponible ahora';
    }
    if (statusMessage.trim().isNotEmpty) return statusMessage;
    return 'Ocupado · vuelve a las $availableTo12h';
  }

  /// Comma-joined coverage cities for compact display, e.g.
  /// "Floridablanca, Girón, Piedecuesta".
  String get coverageSummary => coverageCities.join(', ');

  /// True when the musician marked themself busy with a return time that
  /// has already passed — the trigger for the auto check-out prompt.
  bool get busyWindowExpired {
    final until = busyUntil;
    if (isFree || until == null) return false;
    return DateTime.now().isAfter(until);
  }

  static String _to12h(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final hour24 = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1];
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:$minute $period';
  }
}
