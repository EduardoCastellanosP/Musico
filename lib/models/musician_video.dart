/// One entry in a musician's video portfolio, stored in the
/// `musician_videos` table with the file itself in Supabase Storage
/// (`musician-videos` bucket, under `{musician_id}/...`). Unlike photos
/// (a plain `text[]` on `profiles`), videos need their own row so each one
/// can carry its own [viewsCount].
class MusicianVideo {
  const MusicianVideo({
    required this.id,
    required this.musicianId,
    required this.videoUrl,
    required this.viewsCount,
    required this.createdAt,
    this.thumbnailUrl,
    this.showInProfile = true,
    this.serviceId,
  });

  factory MusicianVideo.fromJson(Map<String, dynamic> json) {
    return MusicianVideo(
      id: json['id'] as String,
      musicianId: json['musician_id'] as String,
      videoUrl: json['video_url'] as String,
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      thumbnailUrl: json['thumbnail_url'] as String?,
      showInProfile: json['show_in_profile'] as bool? ?? true,
      serviceId: json['service_id'] as String?,
    );
  }

  final String id;
  final String musicianId;
  final String videoUrl;
  final int viewsCount;
  final DateTime createdAt;

  /// Lightweight JPEG shown by [VideoFeedScreen] before the real video is
  /// worth downloading — see `supabase/schema.sql`'s `musician_videos`
  /// comment. Null for videos uploaded before this column existed.
  final String? thumbnailUrl;

  /// Whether this video appears in the client-facing "Portafolio" tab
  /// (`ServiceDetailScreen`) — editable any time from `MediaManagerCard`,
  /// independent of the video still living in the owner's own gallery.
  /// See `supabase/schema.sql` §30.
  final bool showInProfile;

  /// Which `provider_services` row this video belongs to — a provider
  /// with several service listings (e.g. "Solista" and "Sonido") needs
  /// each video scoped to the right one, so it doesn't leak into every
  /// other service's portfolio. `null` means "show in all of this
  /// provider's services" (the behavior every video had before this
  /// column existed). See `supabase/schema.sql` §31.
  final String? serviceId;

  MusicianVideo copyWith({int? viewsCount, bool? showInProfile}) {
    return MusicianVideo(
      id: id,
      musicianId: musicianId,
      videoUrl: videoUrl,
      viewsCount: viewsCount ?? this.viewsCount,
      createdAt: createdAt,
      thumbnailUrl: thumbnailUrl,
      showInProfile: showInProfile ?? this.showInProfile,
      serviceId: serviceId,
    );
  }

  /// Separate from [copyWith] because [serviceId] genuinely needs to go
  /// back to `null` ("todos mis servicios") — a plain `?? this.serviceId`
  /// fallback couldn't tell "keep the current value" apart from
  /// "clear it".
  MusicianVideo copyWithServiceId(String? serviceId) {
    return MusicianVideo(
      id: id,
      musicianId: musicianId,
      videoUrl: videoUrl,
      viewsCount: viewsCount,
      createdAt: createdAt,
      thumbnailUrl: thumbnailUrl,
      showInProfile: showInProfile,
      serviceId: serviceId,
    );
  }
}
