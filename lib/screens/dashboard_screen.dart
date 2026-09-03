import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../models/musician.dart';
import '../models/musician_stats.dart';
import '../repositories/musician_repository.dart';
import 'musician_detail_screen.dart';
import 'status_screen.dart';
import 'widgets/complete_profile_prompt.dart';
import 'widgets/dashboard/auto_checkout_dialog.dart';
import 'widgets/dashboard/dashboard_header.dart';
import 'widgets/dashboard/musician_card.dart';
import 'widgets/dashboard/search_filter_bar.dart';

/// Musician directory — the app's home screen. Every list, filter and
/// counter here is backed live by Supabase; nothing is hardcoded.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final MusicianRepository _repository = MusicianRepository();
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription<int>? _countSubscription;
  Timer? _searchDebounce;
  Timer? _autoCheckoutTimer;
  bool _showingCheckoutDialog = false;

  Musician? _currentProfile;
  MusicianStats _stats = MusicianStats.zero;
  List<Musician> _musicians = const [];
  int _availableCount = 0;
  String _search = '';
  String? _selectedInstrument;
  String? _selectedGenre;
  String? _selectedService;
  String? _selectedCityFilter;
  bool _onlyFree = false;
  // Requirement 4 default: "Cercanías" (near the musician's own city). The
  // dashboard's "Toda Colombia" switch flips this to search nationwide.
  bool _searchNationwide = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _countSubscription = _repository.streamAvailableCount().listen((count) {
      if (mounted) setState(() => _availableCount = count);
    });
    // Foreground assistant: while the dashboard is open, periodically check
    // whether the logged-in musician's "ocupado hasta" window has elapsed.
    _autoCheckoutTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _loadProfile(),
    );
    _initialLoad();
  }

  /// Loads the logged-in musician's own profile before the first directory
  /// fetch — the "Cercanías" filter needs `_currentProfile?.city` as
  /// [MusicianRepository.fetchMusicians]'s `nearCity`, so the very first
  /// query the user sees should already be scoped correctly instead of
  /// flashing a nationwide list for a frame.
  Future<void> _initialLoad() async {
    await _loadProfile();
    _loadMusicians();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countSubscription?.cancel();
    _searchDebounce?.cancel();
    _autoCheckoutTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    final profile = await _repository.fetchCurrentProfile();
    if (!mounted) return;
    setState(() => _currentProfile = profile);
    _maybePromptAutoCheckout();

    if (profile != null) {
      final stats = await _repository.fetchContactStats(profile.id);
      if (!mounted) return;
      setState(() => _stats = stats);
    }
  }

  /// Shows the "¿sigues ocupado?" dialog once the musician's own
  /// `busy_until` cutoff has passed while they were still "ocupado".
  void _maybePromptAutoCheckout() {
    final profile = _currentProfile;
    if (profile == null || _showingCheckoutDialog) return;
    if (!profile.busyWindowExpired) return;

    _showingCheckoutDialog = true;
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AutoCheckoutDialog(),
    ).then((result) async {
      _showingCheckoutDialog = false;
      if (result == true) {
        await _repository.markAsFree();
      } else if (result == false) {
        await _repository.snoozeBusyUntil(const Duration(minutes: 30));
      } else {
        return;
      }
      await _loadProfile();
      _loadMusicians();
    });
  }

  Future<void> _loadMusicians() async {
    setState(() => _loading = true);
    try {
      // An explicit city filter (e.g. "Valledupar") overrides the "De mi
      // ciudad"/"Toda Colombia" toggle — it's a more specific choice than
      // either, but reuses the exact same CityZones-widened `nearCity`
      // matching underneath, so a musician in a nearby commuter town still
      // shows up instead of only exact-city matches.
      final musicians = await _repository.fetchMusicians(
        instrument: _selectedInstrument,
        genre: _selectedGenre,
        service: _selectedService,
        onlyFree: _onlyFree,
        search: _search,
        nearCity: _selectedCityFilter ?? _currentProfile?.city,
        searchNationwide: _selectedCityFilter == null && _searchNationwide,
      );
      if (!mounted) return;
      setState(() {
        _musicians = musicians;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No pudimos cargar el directorio. Desliza para reintentar.';
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _search = value;
      _loadMusicians();
    });
  }

  void _onInstrumentSelected(String? instrument) {
    setState(() => _selectedInstrument = instrument);
    _loadMusicians();
  }

  void _onGenreSelected(String? genre) {
    setState(() => _selectedGenre = genre);
    _loadMusicians();
  }

  void _onServiceSelected(String? service) {
    setState(() => _selectedService = service);
    _loadMusicians();
  }

  void _onCityFilterSelected(String? city) {
    setState(() => _selectedCityFilter = city);
    _loadMusicians();
  }

  void _onOnlyFreeChanged(bool value) {
    setState(() => _onlyFree = value);
    _loadMusicians();
  }

  void _onNationwideChanged(bool value) {
    setState(() => _searchNationwide = value);
    _loadMusicians();
  }

  /// Dashboard header's quick availability switch. Flips `_currentProfile`
  /// immediately (optimistic UI) before the network call even starts; if
  /// [MusicianRepository.setAvailability] throws, the flip is rolled back
  /// and the user is told via a [SnackBar].
  Future<void> _onAvailabilityChanged(bool isFree) async {
    final previousProfile = _currentProfile;
    if (previousProfile == null) return;

    setState(() {
      _currentProfile = previousProfile.copyWith(
        isFree: isFree,
        clearBusyUntil: isFree,
      );
    });

    try {
      await _repository.setAvailability(isFree);
    } catch (_) {
      if (!mounted) return;
      setState(() => _currentProfile = previousProfile);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No pudimos actualizar tu disponibilidad.'),
          ),
        );
    }
  }

  Future<void> _openStatusScreen() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StatusScreen()));
    _loadProfile();
    _loadMusicians();
  }

  Future<void> _contact(Musician musician, {required bool isWhatsApp}) async {
  // Browsing the directory never requires a finished profile — only
  // reaching out to someone does. See [Musician.hasCompleteProfile].
  if (!(_currentProfile?.hasCompleteProfile ?? false)) {
    await showCompleteProfilePrompt(context);
    return;
  }

  final Uri uri;

  if (isWhatsApp) {
    // 1. Limpiamos el número para asegurar que solo queden dígitos
    final cleanPhone = musician.phone.replaceAll(RegExp(r'\D'), '');
    
    // 2. Creamos el mensaje con la mención a MUSSY
    final message = '¡Hola ${musician.fullName}! Vi tu perfil y número de contacto en la app de MUSSY y me interesan tus servicios.';
    
    // 3. Construimos la URI con el texto codificado
    uri = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');
  } else {
    // Si es llamada normal, mantiene su comportamiento habitual
    uri = musician.callUri;
  }

  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched) return;

  unawaited(
    _repository.logContactEvent(
      musicianId: musician.id,
      contactType: isWhatsApp ? 'whatsapp' : 'call',
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadProfile();
            await _loadMusicians();
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: DashboardHeader(
                  musicianId: _currentProfile?.id,
                  greetingName: _currentProfile?.fullName,
                  stats: _stats,
                  onSettingsTap: _openStatusScreen,
                  isFree: _currentProfile?.isFree ?? true,
                  onAvailabilityChanged: _onAvailabilityChanged,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              SliverToBoxAdapter(
                child: SearchFilterBar(
                  searchController: _searchController,
                  onSearchChanged: _onSearchChanged,
                  selectedGenre: _selectedGenre,
                  onGenreSelected: _onGenreSelected,
                  selectedInstrument: _selectedInstrument,
                  onInstrumentSelected: _onInstrumentSelected,
                  selectedService: _selectedService,
                  onServiceSelected: _onServiceSelected,
                  selectedCityFilter: _selectedCityFilter,
                  onCityFilterSelected: _onCityFilterSelected,
                  onlyFree: _onlyFree,
                  onOnlyFreeChanged: _onOnlyFreeChanged,
                  searchNationwide: _searchNationwide,
                  onNationwideChanged: _onNationwideChanged,
                  homeCity: _currentProfile?.city,
                ),
              ),
              SliverToBoxAdapter(child: _AvailableCountLabel(count: _availableCount)),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              _buildBody(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _musicians.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }

    if (_error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (_musicians.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No encontramos músicos con esos filtros.'),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final musician = _musicians[index];
        return MusicianCard(
          musician: musician,
          onWhatsAppTap: () => _contact(musician, isWhatsApp: true),
          onCallTap: () => _contact(musician, isWhatsApp: false),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MusicianDetailScreen(musician: musician),
            ),
          ),
        );
      }, childCount: _musicians.length),
    );
  }
}

/// Live "N músicos disponibles ahora" count — moved out of [DashboardHeader]
/// to sit right below [SearchFilterBar]'s "Mostrando músicos cerca de..."
/// caption, since both lines describe the list immediately underneath them.
class _AvailableCountLabel extends StatelessWidget {
  const _AvailableCountLabel({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 20, 0),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF22C55E),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count Músico${count == 1 ? '' : 's'} '
            'disponible${count == 1 ? '' : 's'} ahora',
            style: theme.textTheme.bodySmall?.copyWith(
              color: extension?.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
