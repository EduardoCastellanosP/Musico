import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/provider_unavailability.dart';

/// Every read/write against `provider_unavailability` — see
/// `supabase/schema.sql` §32-33. Full-day and time-slot rows for the same
/// date are mutually exclusive: this class deletes whichever one doesn't
/// apply before writing the new one, so callers never leave a date in an
/// ambiguous mixed state.
class ProviderAvailabilityRepository {
  ProviderAvailabilityRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String _fmtDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _fmtTime(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}:00';

  /// Every blocked row (full-day and time-slot) for [serviceId].
  Future<List<ProviderUnavailability>> fetchAll(String serviceId) async {
    final rows = await _client
        .from('provider_unavailability')
        .select()
        .eq('service_id', serviceId)
        .order('date')
        .order('start_time');
    return rows.map(ProviderUnavailability.fromJson).toList();
  }

  /// Marks [date] fully occupied — any time slots already on that date are
  /// superseded and removed first, since a full-day block makes them moot.
  Future<void> blockFullDay(String serviceId, DateTime date) async {
    final dateStr = _fmtDate(date);
    await _client.from('provider_unavailability').delete().eq('service_id', serviceId).eq('date', dateStr);
    await _client.from('provider_unavailability').insert({'service_id': serviceId, 'date': dateStr});
  }

  /// Clears every block (full-day or slots) on [date], making it available.
  Future<void> unblockDay(String serviceId, DateTime date) async {
    await _client
        .from('provider_unavailability')
        .delete()
        .eq('service_id', serviceId)
        .eq('date', _fmtDate(date));
  }

  /// Adds one time slot to [date] and returns the created row (its `id` is
  /// what [removeSlot] needs later). If that date was blocked as a full
  /// day, the full-day row is removed first — a specific slot means the
  /// rest of the day is meant to stay open.
  Future<ProviderUnavailability> addTimeSlot(
    String serviceId,
    DateTime date,
    int startMinutes,
    int endMinutes,
  ) async {
    final dateStr = _fmtDate(date);
    await _client
        .from('provider_unavailability')
        .delete()
        .eq('service_id', serviceId)
        .eq('date', dateStr)
        .isFilter('start_time', null);
    final row = await _client
        .from('provider_unavailability')
        .insert({
          'service_id': serviceId,
          'date': dateStr,
          'start_time': _fmtTime(startMinutes),
          'end_time': _fmtTime(endMinutes),
        })
        .select()
        .single();
    return ProviderUnavailability.fromJson(row);
  }

  Future<void> removeSlot(String id) async {
    await _client.from('provider_unavailability').delete().eq('id', id);
  }

  /// Blocks every day in [start]..[end] (inclusive) as full days in one
  /// round-trip — used by the range-select mode (vacations/trips). Clears
  /// whatever was on those dates first (full-day or slots) to avoid
  /// leftover rows conflicting with the fresh full-day blocks.
  Future<void> blockRange(String serviceId, DateTime start, DateTime end) async {
    final dates = <String>[];
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      dates.add(_fmtDate(d));
    }
    await _client.from('provider_unavailability').delete().eq('service_id', serviceId).inFilter('date', dates);
    await _client
        .from('provider_unavailability')
        .insert(dates.map((d) => {'service_id': serviceId, 'date': d}).toList());
  }
}
