import '../services/youtube_rss_service.dart';
import 'musician.dart';
import 'musician_video.dart';

/// One card in the Reels-style [VideoFeedScreen]: a [MusicianVideo] plus
/// just enough of its owner's `profiles` row (via the PostgREST embed in
/// `MusicianRepository.fetchVideoFeed`) to render the overlay and let a
/// viewer contact them — a full [Musician] carries fields the feed never
/// shows and would cost an unnecessary embed of its own `musician_videos`.
///
/// [youtubeVideoId] is set instead for a card sourced from a musician's
/// linked YouTube channel (see [VideoFeedItem.youtube]) — [video] is still
/// populated with a synthetic row (id prefixed `yt:`) so every other field
/// on the card keeps working, but it has no real `musician_videos` row, so
/// liking/view-counting it against Supabase is a harmless no-op.
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
    this.youtubeVideoId,
    this.youtubeAspectRatio = 16 / 9,
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

  /// A card for [musician]'s latest YouTube upload — mixed into the feed
  /// alongside native [fromJson] cards by `VideoFeedScreenState._loadInitial`.
  /// [aspectRatio] is the video's real width/height (see
  /// `YoutubeRssService.fetchAspectRatio`) so a vertical Short renders
  /// vertically instead of pillarboxed into a fixed 16:9 frame.
  factory VideoFeedItem.youtube({
    required Musician musician,
    required YoutubeVideo ytVideo,
    double aspectRatio = 16 / 9,
  }) {
    return VideoFeedItem(
      video: MusicianVideo(
        id: 'yt:${ytVideo.videoId}',
        musicianId: musician.id,
        videoUrl: ytVideo.watchUrl,
        viewsCount: 0,
        createdAt: ytVideo.publishedAt ?? DateTime.now(),
      ),
      musicianId: musician.id,
      musicianName: musician.fullName,
      avatarUrl: musician.avatarUrl,
      city: musician.city,
      phone: musician.phone,
      isFree: musician.isFree,
      instruments: musician.instruments,
      genres: musician.genres,
      services: musician.services,
      youtubeVideoId: ytVideo.videoId,
      youtubeAspectRatio: aspectRatio,
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
  final String? youtubeVideoId;

  /// Real width/height for [youtubeVideoId] — see [VideoFeedItem.youtube].
  /// Meaningless (default 16:9) on a native card.
  final double youtubeAspectRatio;

  bool get isYoutube => youtubeVideoId != null;

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
