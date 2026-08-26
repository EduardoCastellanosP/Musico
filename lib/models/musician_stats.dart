/// Aggregated performance metrics for the "Mi Estado" stats panel, computed
/// live from the `contact_events` table (never hardcoded).
class MusicianStats {
  const MusicianStats({
    required this.contactsToday,
    required this.contactsThisMonth,
    required this.followersCount,
    required this.totalVideoLikes,
  });

  final int contactsToday;
  final int contactsThisMonth;

  /// Rows in `musician_follows` where this musician is followed.
  final int followersCount;

  /// Rows in `video_likes` across every video this musician has uploaded.
  final int totalVideoLikes;

  static const zero = MusicianStats(
    contactsToday: 0,
    contactsThisMonth: 0,
    followersCount: 0,
    totalVideoLikes: 0,
  );
}
