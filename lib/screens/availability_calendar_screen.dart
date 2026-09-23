import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/provider_service.dart';
import '../models/provider_unavailability.dart';
import '../repositories/provider_availability_repository.dart';

const _kBackground = Color(0xFF0D0D12);
const _kSurface = Color(0xFF17171D);
const _kAccent = Color(0xFFFFB703);
const _kBlocked = Color(0xFF2A2A32);
const _kTextSecondary = Color(0xFF9A9AA5);

const _kMonthNames = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _formatFullDate(DateTime date) => '${date.day} de ${_kMonthNames[date.month - 1]} de ${date.year}';

String _formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final period = h < 12 ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
}

enum _DayState { free, fullDay, partial }

/// Full-screen availability calendar for ONE `provider_service`. Tapping a
/// day opens [_DayManagerSheet] to block the whole day or add specific
/// occupied time slots; a separate range-select mode blocks several full
/// days at once (vacations/trips). See `supabase/schema.sql` §32-33.
class AvailabilityCalendarScreen extends StatefulWidget {
  const AvailabilityCalendarScreen({super.key, required this.service});

  final ProviderService service;

  @override
  State<AvailabilityCalendarScreen> createState() => _AvailabilityCalendarScreenState();
}

class _AvailabilityCalendarScreenState extends State<AvailabilityCalendarScreen> {
  final _repository = ProviderAvailabilityRepository();

  List<ProviderUnavailability>? _rows;
  String? _error;
  DateTime _focusedDay = _dateOnly(DateTime.now());

  bool _rangeMode = false;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  bool _savingRange = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _rows = null;
    });
    try {
      final rows = await _repository.fetchAll(widget.service.id);
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Map<DateTime, List<ProviderUnavailability>> _groupByDate(List<ProviderUnavailability> rows) {
    final map = <DateTime, List<ProviderUnavailability>>{};
    for (final row in rows) {
      map.putIfAbsent(_dateOnly(row.date), () => []).add(row);
    }
    return map;
  }

  _DayState _stateFor(DateTime day, Map<DateTime, List<ProviderUnavailability>> byDate) {
    final rows = byDate[_dateOnly(day)];
    if (rows == null || rows.isEmpty) return _DayState.free;
    if (rows.any((r) => r.isFullDay)) return _DayState.fullDay;
    return _DayState.partial;
  }

  /// Opens the per-day modal; reloads afterward rather than threading
  /// incremental updates back through it — the list is small, so a fresh
  /// fetch is simpler than keeping two copies of it in sync.
  Future<void> _openDayModal(DateTime day, List<ProviderUnavailability> rowsForDay) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DayManagerSheet(serviceId: widget.service.id, date: day, initialRows: rowsForDay),
    );
    if (mounted) _load();
  }

  void _setRangeMode(bool enabled) {
    setState(() {
      _rangeMode = enabled;
      _rangeStart = null;
      _rangeEnd = null;
    });
  }

  Future<void> _confirmRange() async {
    final start = _rangeStart;
    final end = _rangeEnd ?? start;
    if (start == null || end == null) return;

    setState(() => _savingRange = true);
    try {
      await _repository.blockRange(widget.service.id, start, end);
      await _load();
      if (!mounted) return;
      final days = end.difference(start).inDays + 1;
      setState(() {
        _savingRange = false;
        _rangeMode = false;
        _rangeStart = null;
        _rangeEnd = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$days día(s) bloqueados.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingRange = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo bloquear el rango: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: _kBackground,
        elevation: 0,
        title: Text(
          widget.service.businessName,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          if (_rows != null)
            IconButton(
              tooltip: _rangeMode ? 'Cancelar selección de rango' : 'Bloquear un rango de fechas',
              icon: Icon(
                _rangeMode ? Icons.close : Icons.date_range,
                color: _rangeMode ? _kAccent : Colors.white,
              ),
              onPressed: () => _setRangeMode(!_rangeMode),
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildRangeBar(),
    );
  }

  Widget? _buildRangeBar() {
    if (!_rangeMode || _rangeStart == null) return null;
    final start = _rangeStart!;
    final end = _rangeEnd ?? start;
    final days = end.difference(start).inDays + 1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Bloquear $days día(s)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              onPressed: _savingRange ? null : _confirmRange,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _savingRange
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('Bloquear', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No se pudo cargar el calendario.\n$_error',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Reintentar', style: TextStyle(color: _kAccent))),
          ],
        ),
      );
    }

    final rows = _rows;
    if (rows == null) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    final byDate = _groupByDate(rows);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: _kAccent, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Toca un día para gestionarlo: bloquéalo completo o añade horarios específicos ocupados.',
                    style: TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _legendItem(
                const _RingSwatch(),
                'Hoy',
              ),
              const SizedBox(width: 14),
              _legendItem(
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: _kBlocked, shape: BoxShape.circle)),
                'Ocupado',
              ),
              const SizedBox(width: 14),
              _legendItem(
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: _kAccent, shape: BoxShape.circle)),
                'Parcial',
              ),
              const Spacer(),
              if (_rangeMode)
                const Text('Toca fecha inicio y fin', style: TextStyle(color: _kTextSecondary, fontSize: 12)),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(16)),
          child: TableCalendar(
            firstDay: DateTime.now().subtract(const Duration(days: 365)),
            lastDay: DateTime.now().add(const Duration(days: 730)),
            focusedDay: _focusedDay,
            rangeSelectionMode: _rangeMode ? RangeSelectionMode.toggledOn : RangeSelectionMode.disabled,
            rangeStartDay: _rangeStart,
            rangeEndDay: _rangeEnd,
            onPageChanged: (day) => setState(() => _focusedDay = day),
            onDaySelected: _rangeMode
                ? null
                : (selected, focused) => _openDayModal(selected, byDate[_dateOnly(selected)] ?? const []),
            onRangeSelected: (start, end, focused) {
              setState(() {
                _focusedDay = focused;
                _rangeStart = start;
                _rangeEnd = end;
              });
            },
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              leftChevronIcon: Icon(Icons.chevron_left, color: _kAccent),
              rightChevronIcon: Icon(Icons.chevron_right, color: _kAccent),
            ),
            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(color: _kTextSecondary),
              weekendStyle: TextStyle(color: _kTextSecondary),
            ),
            calendarStyle: const CalendarStyle(
              outsideDaysVisible: false,
              defaultTextStyle: TextStyle(color: _kAccent, fontWeight: FontWeight.w600),
              weekendTextStyle: TextStyle(color: _kAccent, fontWeight: FontWeight.w600),
              rangeStartDecoration: BoxDecoration(color: _kAccent, shape: BoxShape.circle),
              rangeEndDecoration: BoxDecoration(color: _kAccent, shape: BoxShape.circle),
              rangeHighlightColor: Color(0x33FFB703),
              withinRangeTextStyle: TextStyle(color: _kAccent),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) => _dayCell(day, _stateFor(day, byDate)),
              todayBuilder: (context, day, focusedDay) =>
                  _dayCell(day, _stateFor(day, byDate), isToday: true),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dayCell(DateTime day, _DayState state, {bool isToday = false}) {
    final blocked = state == _DayState.fullDay;
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: blocked ? _kBlocked : Colors.transparent,
              shape: BoxShape.circle,
              border: isToday ? Border.all(color: _kAccent, width: 2) : null,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: blocked ? Colors.white38 : _kAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (state == _DayState.partial)
            const Positioned(
              bottom: 2,
              right: 4,
              child: _PartialDot(),
            ),
        ],
      ),
    );
  }

  Widget _legendItem(Widget swatch, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 10, height: 10, child: Center(child: swatch)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 12)),
      ],
    );
  }
}

class _RingSwatch extends StatelessWidget {
  const _RingSwatch();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _kAccent, width: 2)),
    );
  }
}

class _PartialDot extends StatelessWidget {
  const _PartialDot();

  @override
  Widget build(BuildContext context) {
    return Container(width: 6, height: 6, decoration: const BoxDecoration(color: _kAccent, shape: BoxShape.circle));
  }
}

/// Bottom sheet for one specific day: toggle it fully blocked, or add/remove
/// individual occupied time slots (each write goes straight to the
/// repository — there is no separate "save" step).
class _DayManagerSheet extends StatefulWidget {
  const _DayManagerSheet({required this.serviceId, required this.date, required this.initialRows});

  final String serviceId;
  final DateTime date;
  final List<ProviderUnavailability> initialRows;

  @override
  State<_DayManagerSheet> createState() => _DayManagerSheetState();
}

class _DayManagerSheetState extends State<_DayManagerSheet> {
  final _repository = ProviderAvailabilityRepository();

  late bool _isFullDay;
  late List<ProviderUnavailability> _slots;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _isFullDay = widget.initialRows.any((r) => r.isFullDay);
    _slots = widget.initialRows.where((r) => !r.isFullDay).toList();
  }

  Future<void> _setFullDay(bool value) async {
    setState(() => _busy = true);
    try {
      if (value) {
        await _repository.blockFullDay(widget.serviceId, widget.date);
      } else {
        await _repository.unblockDay(widget.serviceId, widget.date);
      }
      if (!mounted) return;
      setState(() {
        _isFullDay = value;
        _slots = [];
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo actualizar: $e')));
    }
  }

  Future<void> _addSlot() async {
    final range = await _showTimeRangePicker(context);
    if (range == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final row = await _repository.addTimeSlot(widget.serviceId, widget.date, range.$1, range.$2);
      if (!mounted) return;
      setState(() {
        _isFullDay = false;
        _slots = [..._slots, row];
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo añadir el horario: $e')));
    }
  }

  Future<void> _removeSlot(ProviderUnavailability slot) async {
    setState(() => _busy = true);
    try {
      await _repository.removeSlot(slot.id);
      if (!mounted) return;
      setState(() {
        _slots = _slots.where((s) => s.id != slot.id).toList();
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatFullDate(widget.date),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: _kAccent,
              value: _isFullDay,
              onChanged: _busy ? null : _setFullDay,
              title: const Text('Bloquear todo el día', style: TextStyle(color: Colors.white)),
            ),
            if (!_isFullDay) ...[
              const Divider(color: Colors.white12),
              const SizedBox(height: 4),
              const Text('Horarios ocupados', style: TextStyle(color: _kTextSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              if (_slots.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Ningún horario específico añadido.',
                    style: TextStyle(color: _kTextSecondary, fontSize: 13),
                  ),
                ),
              ..._slots.map(
                (slot) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, color: _kAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_formatMinutes(slot.startTime!)} - ${_formatMinutes(slot.endTime!)}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: _busy ? null : () => _removeSlot(slot),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _busy ? null : _addSlot,
                icon: const Icon(Icons.add, color: _kAccent),
                label: const Text('Añadir otro horario', style: TextStyle(color: _kAccent)),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Listo', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<(int, int)?> _showTimeRangePicker(BuildContext context) {
  return showModalBottomSheet<(int, int)>(
    context: context,
    backgroundColor: _kSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _TimeRangePickerSheet(),
  );
}

/// iOS-style wheel time pickers (`CupertinoDatePicker`, mode `.time`) for
/// picking the start/end of one occupied slot.
class _TimeRangePickerSheet extends StatefulWidget {
  const _TimeRangePickerSheet();

  @override
  State<_TimeRangePickerSheet> createState() => _TimeRangePickerSheetState();
}

class _TimeRangePickerSheetState extends State<_TimeRangePickerSheet> {
  DateTime _start = DateTime(2024, 1, 1, 8, 0);
  DateTime _end = DateTime(2024, 1, 1, 9, 0);

  int _toMinutes(DateTime t) => t.hour * 60 + t.minute;

  @override
  Widget build(BuildContext context) {
    final valid = _toMinutes(_end) > _toMinutes(_start);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Añadir horario ocupado',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _timeColumn('Inicio', _start, (t) => setState(() => _start = t))),
                Expanded(child: _timeColumn('Fin', _end, (t) => setState(() => _end = t))),
              ],
            ),
            if (!valid)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'La hora de fin debe ser posterior al inicio.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: valid
                    ? () => Navigator.of(context).pop((_toMinutes(_start), _toMinutes(_end)))
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: _kAccent.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Añadir', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeColumn(String label, DateTime value, ValueChanged<DateTime> onChanged) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 13)),
        const SizedBox(height: 4),
        SizedBox(
          height: 160,
          child: CupertinoTheme(
            data: const CupertinoThemeData(brightness: Brightness.dark),
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              initialDateTime: value,
              use24hFormat: false,
              onDateTimeChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
