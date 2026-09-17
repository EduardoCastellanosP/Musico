import 'package:flutter/material.dart';

import '../core/utils/currency.dart';
import '../models/provider_service.dart';
import '../repositories/provider_service_repository.dart';
import '../services/auth_service.dart';
import 'widgets/services/admin_service_detail_modal.dart';
import 'widgets/services/service_cover_image.dart';

const _kBackground = Color(0xFF0D0D12);
const _kSurface = Color(0xFF17171D);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

/// Moderation queue for `provider_services` — only reachable by an admin
/// (`profiles.is_admin`, see `supabase/schema.sql` §18); anyone else's
/// `fetchPendingServices()` just comes back empty because of RLS.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _repository = ProviderServiceRepository();
  final _authService = AuthService();

  List<ProviderService>? _services;
  String? _error;
  final Set<String> _processingIds = {};
  bool _signingOut = false;

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
      final services = await _repository.fetchPendingServices();
      if (!mounted) return;
      setState(() => _services = services);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  /// Returns whether the update succeeded — [AdminServiceDetailModal] uses
  /// that to decide whether to close itself, while [_PendingServiceCard]'s
  /// inline buttons just ignore it (the SnackBar/list update below already
  /// covers that path).
  Future<bool> _review(ProviderService service, {required bool approve}) async {
    setState(() => _processingIds.add(service.id));
    try {
      await _repository.updateServiceStatus(
        serviceId: service.id,
        newStatus: approve ? 'approved' : 'rejected',
        isVerified: approve,
      );

      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Servicio aprobado con éxito.' : 'Servicio rechazado.',
          ),
        ),
      );
      setState(() {
        _services?.removeWhere((s) => s.id == service.id);
        _processingIds.remove(service.id);
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar el servicio: $e')),
      );
      setState(() => _processingIds.remove(service.id));
      return false;
    }
  }

  void _openDetail(ProviderService service) {
    showAdminServiceDetailModal(
      context,
      service: service,
      onApprove: () => _review(service, approve: true),
      onReject: () => _review(service, approve: false),
    );
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
        content: const Text(
          '¿Estás seguro que deseas cerrar sesión?',
          style: TextStyle(color: _kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: _kTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cerrar sesión', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // No manual navigation: `AuthGate`'s `StreamBuilder` reacts to
    // `onAuthStateChange` and swaps back to `LoginScreen` on its own once
    // the session clears, the same way it swapped to this screen in the
    // first place.
    setState(() => _signingOut = true);
    try {
      await _authService.signOut();
    } catch (e) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cerrar sesión: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: _kSurface,
        foregroundColor: Colors.white,
        title: const Text('Panel de Moderación - Mussy'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: _signingOut
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
                  )
                : const Icon(Icons.logout_rounded, color: _kAccent),
            onPressed: _signingOut ? null : _confirmSignOut,
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    final services = _services;
    if (services == null) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (services.isEmpty) {
      return _EmptyState(onRefresh: _load);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];
        return _PendingServiceCard(
          service: service,
          processing: _processingIds.contains(service.id),
          onTapDetail: () => _openDetail(service),
          onApprove: () => _review(service, approve: true),
          onReject: () => _review(service, approve: false),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, color: _kTextSecondary, size: 40),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'No se pudieron cargar los servicios pendientes.\n$message',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: const Text('Reintentar', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.task_alt, color: _kAccent, size: 48),
          const SizedBox(height: 16),
          const Text(
            'No hay servicios pendientes por revisar',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          IconButton(
            icon: const Icon(Icons.refresh, color: _kTextSecondary),
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _PendingServiceCard extends StatelessWidget {
  const _PendingServiceCard({
    required this.service,
    required this.processing,
    required this.onTapDetail,
    required this.onApprove,
    required this.onReject,
  });

  final ProviderService service;
  final bool processing;
  final VoidCallback onTapDetail;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTapDetail,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: ServiceCoverImage(
                    url: service.coverPhotoUrl,
                    width: double.infinity,
                    height: 160,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              service.businessName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (service.pricePerHour != null)
                            Text(
                              formatCopPerHour(service.pricePerHour!),
                              style: const TextStyle(
                                color: _kAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          service.category.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        service.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _kTextSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onTapDetail,
                          child: const Text(
                            'Ver detalles',
                            style: TextStyle(color: _kAccent, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: processing ? null : onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                        child: const Text('Rechazar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: processing ? null : onApprove,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: Colors.black,
                        ),
                        child: processing
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Text('Aprobar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
