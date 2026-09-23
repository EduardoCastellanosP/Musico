/// A single blocked row for one `provider_services`, either a full day
/// (`startTime`/`endTime` both null) or a specific time slot within a day
/// — see `supabase/schema.sql` §32-33. A date can have many slot rows but
/// at most one full-day row.
class ProviderUnavailability {
  const ProviderUnavailability({
    required this.id,
    required this.serviceId,
    required this.date,
    this.startTime,
    this.endTime,
  });

  factory ProviderUnavailability.fromJson(Map<String, dynamic> json) {
    return ProviderUnavailability(
      id: json['id'] as String,
      serviceId: json['service_id'] as String,
      date: DateTime.parse(json['date'] as String),
      startTime: _parseTime(json['start_time'] as String?),
      endTime: _parseTime(json['end_time'] as String?),
    );
  }

  final String id;
  final String serviceId;
  final DateTime date;

  /// Minutes since midnight. Null on both means the whole day is blocked.
  final int? startTime;
  final int? endTime;

  bool get isFullDay => startTime == null && endTime == null;

  static int? _parseTime(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}
