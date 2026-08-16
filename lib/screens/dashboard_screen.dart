import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../models/musician.dart';
import '../repositories/musician_repository.dart';
import 'musician_detail_screen.dart';
import 'status_screen.dart';
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
  List<Musician> _musicians = const [];
  int _availableCount = 0;
  String _search = '';
  String? _selectedInstrument;
  String? _selectedGenre;
  String? _selectedService;
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
      final musicians = await _repository.fetchMusicians(
        instrument: _selectedInstrument,
        genre: _selectedGenre,
        service: _selectedService,
        onlyFree: _onlyFree,
        search: _search,
        nearCity: _currentProfile?.city,
        searchNationwide: _searchNationwide,
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

  void _onOnlyFreeChanged(bool value) {
    setState(() => _onlyFree = value);
    _loadMusicians();
  }

  void _onNationwideChanged(bool value) {
    setState(() => _searchNationwide = value);
    _loadMusicians();
  }

  Future<void> _openStatusScreen() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StatusScreen()));
    _loadProfile();
    _loadMusicians();
  }

  Future<void> _contact(Musician musician, {required bool isWhatsApp}) async {
    final uri = isWhatsApp ? musician.whatsappUri : musician.callUri;
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
                  greetingName: _currentProfile?.fullName,
                  availableCount: _availableCount,
                  onSettingsTap: _openStatusScreen,
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
                  onlyFree: _onlyFree,
                  onOnlyFreeChanged: _onOnlyFreeChanged,
                  searchNationwide: _searchNationwide,
                  onNationwideChanged: _onNationwideChanged,
                  homeCity: _currentProfile?.city,
                ),
              ),
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
