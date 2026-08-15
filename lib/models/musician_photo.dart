/// One entry in a musician's live-performance photo portfolio, stored in
/// the `musician_photos` table with the file itself in Supabase Storage
/// (`musician-photos` bucket, under `{musician_id}/...`).
class MusicianPhoto {
  const MusicianPhoto({
    required this.id,
    required this.musicianId,
    required this.imageUrl,
    required this.createdAt,
  });

  factory MusicianPhoto.fromJson(Map<String, dynamic> json) {
    return MusicianPhoto(
      id: json['id'] as String,
      musicianId: json['musician_id'] as String,
      imageUrl: json['image_url'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String musicianId;
  final String imageUrl;
  final DateTime createdAt;
}
