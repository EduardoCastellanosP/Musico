import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/currency.dart';
import '../models/provider_service.dart';
import '../repositories/client_repository.dart';
import '../repositories/provider_service_repository.dart';
import 'client_profile_screen.dart';
import 'my_bookings_screen.dart';
import 'saved_services_screen.dart';
import 'service_detail_screen.dart';
import 'widgets/client/animated_search_field.dart';
import 'widgets/client/city_picker_modal.dart';
import 'widgets/client/nightclub_card.dart';
import 'widgets/services/service_cover_image.dart';
import 'widgets/services/service_list_card.dart';

// Tarima's own dark palette — deliberately not `AppColors` (that's the
// Backstage/social-app theme).
const _kBackground = Color(0xFF0D0D12);
const _kSurface = Color(0xFF17171D);
// Search bar / inactive chip fill — explicitly a shade lighter than
// `_kSurface` per the Tarima design spec, not just reusing the card color.
const _kInputSurface = Color(0xFF1E1E2C);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

// Genuine "Playfair Display" would need either a bundled font asset or the
// `google_fonts` package — neither exists in this project yet, and pulling
// in a whole package for two headings is more than this earns. `'serif'` is
// a generic family Flutter resolves to the platform's built-in serif face
// (Georgia-ish on most platforms), which is what the design brief's own "o
// similar" allows.
// ponytail: generic serif fallback, not the exact Playfair Display face —
// swap to google_fonts' GoogleFonts.playfairDisplay() if pixel-exact
// branding ever matters more than the extra dependency.
const _kSerifFontFamily = 'serif';

const _kFilters = ['Todos', 'Agrupaciones', 'DJs & Sonido', 'Solistas', 'Ocio & Discotecas'];

/// Categories (as stored in `provider_services.category`) each filter chip
/// matches — empty means "no filter" (the "Todos" chip). "Ensayadero" has
/// no chip of its own, so it only ever shows up under "Todos".
const Map<String, List<String>> _kFilterCategories = {
  'Agrupaciones': ['Agrupación'],
  'DJs & Sonido': ['DJ', 'Sonido'],
  'Solistas': ['Solista'],
  'Ocio & Discotecas': ['Discoteca'],
};

/// The one category rendered as [NightclubCard] instead of
/// [ServiceListCard] in the "Todos los actos" list — see
/// `supabase/schema.sql` §23.
const _kNightclubCategory = 'Discoteca';

/// Default city shown/filtered by before the user ever opens the picker.
/// Extension point for real geolocation later (e.g. `geolocator` +
/// reverse geocoding to the nearest `ColombiaCities` municipio) — that's a
/// new dependency plus Android/iOS location-permission plumbing, which is
/// more than this task asked for, so today it's just a fixed default.
const _kDefaultCity = 'Bucaramanga';

/// The Tarima "Explorar" screen — lists approved `provider_services` rows
/// for a client to browse. See `supabase/schema.sql` §17.
class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

typedef _HomeData = ({List<ProviderService> services, Set<String> savedIds});

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  final _repository = ProviderServiceRepository();
  final _clientRepository = ClientRepository();
  late Future<_HomeData> _dataFuture;
  String _selectedFilter = _kFilters.first;
  String _selectedCity = _kDefaultCity;

  // Anchor for "VER TODOS" to scroll to, rather than pushing a second
  // screen that would just re-render the same list-building logic this
  // `CustomScrollView` already has inline.
  final _allActsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<_HomeData> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final results = await Future.wait([
      _repository.fetchApprovedServices(),
      uid == null ? Future.value(<ProviderService>[]) : _clientRepository.fetchSavedServices(uid),
    ]);
    final services = results[0];
    final savedIds = results[1].map((s) => s.id).toSet();
    return (services: services, savedIds: savedIds);
  }

  void _retry() {
    setState(() => _dataFuture = _load());
  }

  Future<void> _pickCity() async {
    final city = await showCityPickerModal(context, currentCity: _selectedCity);
    if (city != null) setState(() => _selectedCity = city);
  }

  void _scrollToAllActs() {
    setState(() => _selectedFilter = 'Todos');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _allActsKey.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _toggleSaved(String serviceId, bool saved) {
    return saved
        ? _clientRepository.saveService(serviceId)
        : _clientRepository.unsaveService(serviceId);
  }

  /// Narrows to the selected municipio by the owner's `profiles.city`
  /// (embedded by `fetchApprovedServices`) — client-side, same as the
  /// category filter below, since the full approved list is already in
  /// memory and re-querying Supabase per city tap would just add latency
  /// picking a card should feel instant, not wait on a round trip.
  List<ProviderService> _applyCityFilter(List<ProviderService> services) {
    if (_selectedCity == kAnyCity) return services;
    final target = _selectedCity.trim().toLowerCase();
    return services.where((s) => s.ownerCity?.trim().toLowerCase() == target).toList();
  }

  List<ProviderService> _applyCategoryFilter(List<ProviderService> services) {
    final categories = _kFilterCategories[_selectedFilter];
    if (categories == null) return services;
    return services.where((s) => categories.contains(s.category)).toList();
  }

  void _openDetail(ProviderService service) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ServiceDetailScreen(service: service)),
    );
  }

  void _showNightclubComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Próximamente: Detalles y reservas')),
    );
  }

  String _locationQueryFor(ProviderService service) {
    final city = service.ownerCity?.trim();
    return (city == null || city.isEmpty) ? service.businessName : '${service.businessName}, $city';
  }

  Widget _buildCard(ProviderService service, Set<String> savedIds) {
    if (service.category == _kNightclubCategory) {
      return NightclubCard(
        service: service,
        locationQuery: _locationQueryFor(service),
        onTap: _showNightclubComingSoon,
      );
    }
    return ServiceListCard(
      service: service,
      isSaved: savedIds.contains(service.id),
      onToggleSaved: (saved) => _toggleSaved(service.id, saved),
      onTap: () => _openDetail(service),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      body: SafeArea(
        child: FutureBuilder<_HomeData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: _kAccent),
              );
            }
            if (snapshot.hasError) {
              return _ErrorState(onRetry: _retry);
            }

            final data = snapshot.data!;
            final savedIds = data.savedIds;
            final inCity = _applyCityFilter(data.services);
            final filtered = _applyCategoryFilter(inCity);
            final listTitle = _selectedFilter == 'Todos'
                ? 'Todos los actos'
                : _selectedFilter;

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(city: _selectedCity, onTapLocation: _pickCity),
                ),
                const SliverToBoxAdapter(child: AnimatedSearchField()),
                SliverToBoxAdapter(
                  child: _FilterChips(
                    selected: _selectedFilter,
                    onSelected: (filter) =>
                        setState(() => _selectedFilter = filter),
                  ),
                ),
                if (inCity.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'Destacados',
                      trailing: TextButton(
                        onPressed: _scrollToAllActs,
                        child: const Text(
                          'VER TODOS',
                          style: TextStyle(
                            color: _kAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _FeaturedCarousel(services: inCity.take(6).toList()),
                  ),
                ],
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    key: _allActsKey,
                    title: listTitle,
                    subtitle: '${filtered.length} disponibles',
                  ),
                ),
                if (filtered.isEmpty)
                  SliverToBoxAdapter(
                    child: _EmptyState(city: _selectedCity),
                  )
                else
                  SliverList.list(
                    children: filtered.map((service) => _buildCard(service, savedIds)).toList(),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: const _ClientBottomBar(),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, color: _kTextSecondary, size: 40),
          const SizedBox(height: 12),
          const Text(
            'No se pudieron cargar los servicios.',
            style: TextStyle(color: Colors.white),
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
  const _EmptyState({required this.city});

  final String city;

  @override
  Widget build(BuildContext context) {
    final where = city == kAnyCity ? '' : ' en $city';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Center(
        child: Text(
          'Aún no hay servicios disponibles$where para esta categoría.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _kTextSecondary),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.city, required this.onTapLocation});

  final String city;
  final VoidCallback onTapLocation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UBICACIÓN',
                  style: TextStyle(
                    color: Color(0xFFB08D3E),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: onTapLocation,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          city == kAnyCity ? Icons.public : Icons.location_on,
                          color: _kAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          city,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: _kAccent, width: 2)),
            ),
            child: const CircleAvatar(
              radius: 18,
              backgroundColor: _kSurface,
              child: Icon(Icons.person, color: _kTextSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        itemCount: _kFilters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final filter = _kFilters[index];
          final active = filter == selected;
          return ChoiceChip(
            label: Text(filter),
            selected: active,
            onSelected: (_) => onSelected(filter),
            backgroundColor: _kInputSurface,
            selectedColor: _kAccent,
            labelStyle: TextStyle(
              color: active ? Colors.black : Colors.white,
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide.none,
            ),
          );
        },
      ),
    );
  }
}

/// Section title in the design's serif face, with an optional trailing
/// action (Destacados' "VER TODOS") or subtitle (the list's "N disponibles"
/// count) — never both, so the two calls below just pick whichever applies.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.title, this.trailing, this.subtitle});

  final String title;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFamily: _kSerifFontFamily,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(color: _kTextSecondary, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _FeaturedCarousel extends StatelessWidget {
  const _FeaturedCarousel({required this.services});

  final List<ProviderService> services;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: services.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) => _FeaturedCard(service: services[index]),
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.service});

  final ProviderService service;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: 190,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ServiceCoverImage(url: service.coverPhotoUrl, width: 190, height: 280),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: ServiceGenreBadge(text: service.category.toUpperCase()),
            ),
            if (service.isVerified)
              const Positioned(top: 12, right: 12, child: ServiceVerifiedBadge()),
            Positioned(
              bottom: 14,
              left: 14,
              right: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.businessName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ServiceRatingRow(rating: service.rating, reviewsCount: service.reviewsCount),
                  const SizedBox(height: 6),
                  if (service.pricePerHour != null)
                    Text(
                      formatCopPrice(service.pricePerHour!),
                      style: const TextStyle(
                        color: _kAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Static 4-tab bottom bar — each tab pushes its screen as a route rather
/// than switching an `IndexedStack` index, since this bar isn't wrapped in
/// its own shell (unlike `HomeShell`'s). Fine for now with 4 independent
/// screens; worth revisiting if a shared bottom bar across pushed routes
/// ever becomes the norm here.
class _ClientBottomBar extends StatelessWidget {
  const _ClientBottomBar();

  @override
  Widget build(BuildContext context) {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: _kSurface,
        indicatorColor: _kAccent.withValues(alpha: 0.2),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? _kAccent : Colors.white60,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? _kAccent : Colors.white60);
        }),
      ),
      child: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          final Widget screen;
          switch (index) {
            case 1:
              screen = const SavedServicesScreen();
            case 2:
              screen = const MyBookingsScreen();
            case 3:
              screen = const ClientProfileScreen();
            default:
              return;
          }
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Explorar'),
          NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            label: 'Guardados',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Mis eventos',
          ),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), label: 'Perfil'),
        ],
      ),
    );
  }
}
