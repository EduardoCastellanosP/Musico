/// Aggregated performance metrics for the "Mi Estado" stats panel, computed
/// live from the `contact_events` table (never hardcoded).
class MusicianStats {
  const MusicianStats({
    required this.contactsToday,
    required this.contactsThisMonth,
  });

  final int contactsToday;
  final int contactsThisMonth;

  static const zero = MusicianStats(contactsToday: 0, contactsThisMonth: 0);
}
