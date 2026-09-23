import 'package:flutter/material.dart';

import '../models/provider_service.dart';
import '../repositories/provider_service_repository.dart';
import 'availability_calendar_screen.dart';
import 'widgets/services/create_service_modal.dart';
import 'widgets/services/provider_service_management_card.dart';

const _kBackground = Color(0xFF0D0D12);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

/// "Mis Servicios" — a provider's own `provider_services` listings
/// (musician, DJ, discoteca...), any status, with edit/delete management.
/// See `supabase/schema.sql` §17 for the table and its RLS.
class MyServicesScreen extends StatefulWidget {
  const MyServicesScreen({super.key});

  @override
  State<MyServicesScreen> createState() => _MyServicesScreenState();
}

class _MyServicesScreenState extends State<MyServicesScreen> {
  final _repository = ProviderServiceRepository();

  List<ProviderService>? _services;
  String? _error;
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _services = null;
    });
    try {
      final services = await _repository.fetchMyServices();
      if (!mounted) return;
      setState(() => _services = services);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _openCreateModal() async {
    await showCreateServiceModal(context);
    if (mounted) _load();
  }

  Future<void> _openEditModal(ProviderService service) async {
    final saved = await showEditServiceModal(context, service);
    if (saved == true && mounted) _load();
  }

  void _openAvailability(ProviderService service) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AvailabilityCalendarScreen(service: service)),
    );
  }

  Future<void> _confirmDelete(ProviderService service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: _kBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¿Eliminar este servicio?',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                '"${service.businessName}" se eliminará permanentemente. Esta acción no se puede deshacer.',
                style: const TextStyle(color: _kTextSecondary, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar', style: TextStyle(color: _kTextSecondary)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Eliminar', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _processingIds.add(service.id));
    try {
      await _repository.deleteService(service.id);
      if (!mounted) return;
      setState(() {
        _services?.removeWhere((s) => s.id == service.id);
        _processingIds.remove(service.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${service.businessName}" fue eliminado.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _processingIds.remove(service.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: _kBackground,
        elevation: 0,
        title: const Text('Mis Servicios', style: TextStyle(color: Colors.white)),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _kAccent,
        foregroundColor: Colors.black,
        onPressed: _openCreateModal,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: _kTextSecondary, size: 40),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'No se pudieron cargar tus servicios.\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
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

    final services = _services;
    if (services == null) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (services.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.queue_music, size: 64, color: _kTextSecondary),
              const SizedBox(height: 20),
              const Text(
                'Aún no has creado ningún servicio',
                textAlign: TextAlign.center,
                style: TextStyle(color: _kTextSecondary, fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _openCreateModal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Subir a la Tarima', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _kAccent,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        itemCount: services.length,
        itemBuilder: (context, index) {
          final service = services[index];
          return ProviderServiceManagementCard(
            service: service,
            busy: _processingIds.contains(service.id),
            onEdit: () => _openEditModal(service),
            onDelete: () => _confirmDelete(service),
            onAvailability: () => _openAvailability(service),
          );
        },
      ),
    );
  }
}
