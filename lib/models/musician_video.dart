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
  });

  factory MusicianVideo.fromJson(Map<String, dynamic> json) {
    return MusicianVideo(
      id: json['id'] as String,
      musicianId: json['musician_id'] as String,
      videoUrl: json['video_url'] as String,
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String musicianId;
  final String videoUrl;
  final int viewsCount;
  final DateTime createdAt;

  MusicianVideo copyWith({int? viewsCount}) {
    return MusicianVideo(
      id: id,
      musicianId: musicianId,
      videoUrl: videoUrl,
      viewsCount: viewsCount ?? this.viewsCount,
      createdAt: createdAt,
    );
  }
}
