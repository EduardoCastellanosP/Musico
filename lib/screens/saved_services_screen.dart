import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/provider_service.dart';
import '../repositories/client_repository.dart';
import 'service_detail_screen.dart';
import 'widgets/client/explore_empty_state.dart';
import 'widgets/services/service_list_card.dart';

const _kBackground = Color(0xFF0D0D12);
const _kAccent = Color(0xFFFFB703);

/// "Artistas Guardados" — a client's favorited `provider_services` rows.
/// Reuses [ServiceListCard] (the same card `ClientHomeScreen`'s list
/// uses) wrapped in a [Dismissible] for swipe-to-remove.
class SavedServicesScreen extends StatefulWidget {
  const SavedServicesScreen({super.key});

  @override
  State<SavedServicesScreen> createState() => _SavedServicesScreenState();
}

class _SavedServicesScreenState extends State<SavedServicesScreen> {
  final _repository = ClientRepository();
  List<ProviderService>? _services;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _services = null;
      _error = null;
    });
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      final services = await _repository.fetchSavedServices(uid);
      if (!mounted) return;
      setState(() => _services = services);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _remove(ProviderService service, int index) async {
    setState(() => _services?.removeAt(index));
    try {
      await _repository.unsaveService(service.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${service.businessName} quitado de guardados.'),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () async {
              try {
                await _repository.saveService(service.id);
                if (mounted) setState(() => _services?.insert(index, service));
              } catch (_) {
                // Best-effort undo — if it fails the item just stays
                // removed, same as if "Deshacer" had never been tapped.
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _services?.insert(index, service));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo quitar: $e')),
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
        title: const Text('Artistas guardados', style: TextStyle(color: Colors.white)),
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
              'No se pudieron cargar tus favoritos.\n$_error',
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

    final services = _services;
    if (services == null) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (services.isEmpty) {
      return const ExploreEmptyState(
        icon: Icons.heart_broken_rounded,
        message: 'Aún no tienes artistas guardados.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];
        return Dismissible(
          key: ValueKey(service.id),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          ),
          onDismissed: (_) => _remove(service, index),
          child: ServiceListCard(
            service: service,
            isSaved: true,
            onToggleSaved: (saved) => saved ? _repository.saveService(service.id) : _remove(service, index),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ServiceDetailScreen(service: service)),
            ),
          ),
        );
      },
    );
  }
}
