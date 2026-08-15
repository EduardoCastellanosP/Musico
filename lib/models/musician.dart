import '../core/constants/genres.dart';

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
    required this.instrument,
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
    required this.genre,
    required this.coverageCities,
    required this.busyUntil,
  });

  factory Musician.fromJson(Map<String, dynamic> json) {
    return Musician(
      id: json['id'] as String,
      fullName: (json['full_name'] as String?)?.trim().isNotEmpty == true
          ? json['full_name'] as String
          : 'Músico sin nombre',
      instrument: json['instrument'] as String? ?? '',
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
      genre: (json['genre'] as String?)?.trim().isNotEmpty == true
          ? json['genre'] as String
          : MusicGenres.fallback,
      coverageCities:
          (json['coverage_cities'] as List<dynamic>?)
              ?.map((city) => city as String)
              .toList() ??
          const [],
      busyUntil: json['busy_until'] != null
          ? DateTime.tryParse(json['busy_until'] as String)
          : null,
    );
  }

  final String id;
  final String fullName;
  final String instrument;
  final String city;
  final int experienceYears;
  final double rating;
  final int reviewsCount;
  final bool isFree;
  final String statusMessage;

  /// 24h "HH:mm", e.g. "22:00".
  final String availableFrom;

  /// 24h "HH:mm", e.g. "06:00".
  final String availableTo;

  final String phone;
  final String? avatarUrl;
  final String genre;

  /// Extra municipalities the musician travels to, beyond their base [city].
  final List<String> coverageCities;

  /// Scheduled end of the current "ocupado" window, used by the dashboard's
  /// auto check-out assistant. Null while free or when no limit was set.
  final DateTime? busyUntil;

  Musician copyWith({
    String? fullName,
    String? instrument,
    String? city,
    String? phone,
    String? genre,
    List<String>? coverageCities,
    bool? isFree,
    String? statusMessage,
    String? availableFrom,
    String? availableTo,
    DateTime? busyUntil,
    bool clearBusyUntil = false,
  }) {
    return Musician(
      id: id,
      fullName: fullName ?? this.fullName,
      instrument: instrument ?? this.instrument,
      city: city ?? this.city,
      experienceYears: experienceYears,
      rating: rating,
      reviewsCount: reviewsCount,
      isFree: isFree ?? this.isFree,
      statusMessage: statusMessage ?? this.statusMessage,
      availableFrom: availableFrom ?? this.availableFrom,
      availableTo: availableTo ?? this.availableTo,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl,
      genre: genre ?? this.genre,
      coverageCities: coverageCities ?? this.coverageCities,
      busyUntil: clearBusyUntil ? null : (busyUntil ?? this.busyUntil),
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

  /// e.g. "Libre desde las 10:00 PM" when free, or the musician's own
  /// status message (falling back to their return time) when busy.
  String get availabilityLabel {
    if (isFree) return 'Libre desde las $availableFrom12h';
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
