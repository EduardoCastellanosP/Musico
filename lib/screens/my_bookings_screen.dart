import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/booking.dart';
import '../repositories/client_repository.dart';
import 'widgets/client/explore_empty_state.dart';
import 'widgets/services/service_cover_image.dart';

const _kBackground = Color(0xFF0D0D12);
const _kSurface = Color(0xFF17171D);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

const _kMonthNames = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String _formatEventDate(DateTime date) =>
    '${date.day} ${_kMonthNames[date.month - 1]} ${date.year}';

/// "Mis Reservas / Eventos" — a client's `bookings` rows against
/// `provider_services`. Read-only for now: no cancel/reschedule action,
/// since the booking-creation flow this screen previews doesn't exist yet
/// either (see `ClientRepository.createBooking`).
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  final _repository = ClientRepository();
  List<Booking>? _bookings;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _bookings = null;
      _error = null;
    });
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      final bookings = await _repository.fetchMyBookings(uid);
      if (!mounted) return;
      setState(() => _bookings = bookings);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: _kBackground,
        elevation: 0,
        title: const Text('Mis reservas', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No se pudieron cargar tus reservas.\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              child: const Text('Reintentar', style: TextStyle(color: _kAccent)),
            ),
          ],
        ),
      );
    }

    final bookings = _bookings;
    if (bookings == null) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (bookings.isEmpty) {
      return const ExploreEmptyState(
        icon: Icons.event_busy_rounded,
        message: 'No tienes reservas activas.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: bookings.length,
      itemBuilder: (context, index) => _BookingCard(booking: bookings[index]),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ServiceCoverImage(
                    url: booking.serviceCoverUrl,
                    width: 68,
                    height: 68,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 90),
                        child: Text(
                          booking.serviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 13, color: _kTextSecondary),
                          const SizedBox(width: 5),
                          Text(
                            _formatEventDate(booking.eventDate),
                            style: const TextStyle(color: _kTextSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(top: 10, right: 10, child: _StatusBadge(status: booking.status)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'pending_advance' => ('Pendiente de Adelanto', _kAccent),
      'confirmed' => ('Confirmado', Colors.greenAccent),
      'cancelled' => ('Cancelado', Colors.redAccent),
      'completed' => ('Completado', _kTextSecondary),
      _ => (status, _kTextSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
