import 'musician_video.dart';

/// One card in the Reels-style [VideoFeedScreen]: a [MusicianVideo] plus
/// just enough of its owner's `profiles` row (via the PostgREST embed in
/// `MusicianRepository.fetchVideoFeed`) to render the overlay and let a
/// viewer contact them — a full [Musician] carries fields the feed never
/// shows and would cost an unnecessary embed of its own `musician_videos`.
class VideoFeedItem {
  const VideoFeedItem({
    required this.video,
    required this.musicianId,
    required this.musicianName,
    required this.avatarUrl,
    required this.city,
    required this.phone,
    required this.isFree,
    required this.instruments,
    required this.genres,
    required this.services,
  });

  factory VideoFeedItem.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>? ?? const {};
    return VideoFeedItem(
      video: MusicianVideo.fromJson(json),
      musicianId: json['musician_id'] as String,
      musicianName: (profile['full_name'] as String?)?.trim().isNotEmpty == true
          ? profile['full_name'] as String
          : 'Músico sin nombre',
      avatarUrl: profile['avatar_url'] as String?,
      city: profile['city'] as String? ?? '',
      phone: profile['phone'] as String? ?? '',
      isFree: profile['is_free'] as bool? ?? false,
      instruments: _stringList(profile['instruments']),
      genres: _stringList(profile['genres']),
      services: _stringList(profile['services']),
    );
  }

  static List<String> _stringList(dynamic value) =>
      (value as List<dynamic>?)?.map((item) => item as String).toList() ??
      const [];

  final MusicianVideo video;
  final String musicianId;
  final String musicianName;
  final String? avatarUrl;
  final String city;
  final String phone;
  final bool isFree;
  final List<String> instruments;
  final List<String> genres;
  final List<String> services;

  String get _digitsOnlyPhone => phone.replaceAll(RegExp(r'[^0-9]'), '');

  bool get hasPhone => _digitsOnlyPhone.isNotEmpty;

  Uri get whatsappUri => Uri.parse(
        'https://wa.me/$_digitsOnlyPhone?text=${Uri.encodeComponent(
          '¡Hola $musicianName! Vi tu video en MUSSY y me interesan tus servicios.',
        )}',
      );

  Uri get callUri => Uri(scheme: 'tel', path: _digitsOnlyPhone);

  /// Comma-joined instruments/services for the overlay's subtitle line,
  /// mirroring `Musician.instrumentsSummary`'s fallback to [services].
  String get subtitle =>
      instruments.isNotEmpty ? instruments.join(', ') : services.join(', ');
}
