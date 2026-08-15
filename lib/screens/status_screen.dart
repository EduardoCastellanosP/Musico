import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants/services.dart';
import '../core/theme/app_theme.dart';
import '../models/musician.dart';
import '../models/musician_photo.dart';
import '../models/musician_stats.dart';
import '../repositories/musician_repository.dart';
import '../services/notification_service.dart';
import 'widgets/status/availability_time_card.dart';
import 'widgets/status/coverage_cities_card.dart';
import 'widgets/status/gallery_card.dart';
import 'widgets/status/message_field_card.dart';
import 'widgets/status/musician_skills_card.dart';
import 'widgets/status/profile_info_card.dart';
import 'widgets/status/service_inventory_card.dart';
import 'widgets/status/services_card.dart';
import 'widgets/status/stats_panel.dart';
import 'widgets/status/status_switch_card.dart';

/// "Mi Estado" — where a musician controls their own availability. Every
/// field here maps 1:1 to a column on their `profiles` row; saving performs
/// a single atomic update guarded by Supabase RLS (`auth.uid() = id`).
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen>
    with WidgetsBindingObserver {
  final MusicianRepository _repository = MusicianRepository();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _coverageCityController = TextEditingController();
  final TextEditingController _availabilityNoteController =
      TextEditingController();
  final TextEditingController _serviceDescriptionController =
      TextEditingController();

  Musician? _profile;
  MusicianStats _stats = MusicianStats.zero;
  List<MusicianPhoto> _photos = const [];
  List<String> _coverageCities = [];
  TimeOfDay _availableFrom = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _availableTo = const TimeOfDay(hour: 22, minute: 0);
  List<String> _selectedInstruments = [];
  List<String> _selectedGenres = [];
  List<String> _selectedServices = [];
  bool _isFree = true;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;

  bool get _isMusician => _selectedServices.contains(MusicianServices.musician);

  bool get _hasTechnicalService =>
      _selectedServices.any(MusicianServices.technical.contains);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _fullNameController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
    _coverageCityController.dispose();
    _availabilityNoteController.dispose();
    _serviceDescriptionController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keeps the Libre/Ocupado switch in sync when the "Sí, ya estoy libre"
    // notification action updated Supabase directly from a background
    // isolate while this screen was already open.
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await _repository.fetchCurrentProfile();
    if (profile == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final results = await Future.wait([
      _repository.fetchContactStats(profile.id),
      _repository.fetchPhotos(profile.id),
    ]);
    final stats = results[0] as MusicianStats;
    final photos = results[1] as List<MusicianPhoto>;

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _stats = stats;
      _photos = photos;
      _isFree = profile.isFree;
      _messageController.text = profile.statusMessage;
      _fullNameController.text = profile.fullName;
      _cityController.text = profile.city;
      _phoneController.text = _localPhoneDigits(profile.phone);
      _coverageCities = List<String>.from(profile.coverageCities);
      _selectedInstruments = List<String>.from(profile.instruments);
      _selectedGenres = List<String>.from(profile.genres);
      _selectedServices = List<String>.from(profile.services);
      _availabilityNoteController.text = profile.availabilityNote;
      _serviceDescriptionController.text = profile.serviceDescription;
      _availableFrom = _parseTime(profile.availableFrom);
      _availableTo = _parseTime(profile.availableTo);
      _loading = false;
    });
  }

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return const TimeOfDay(hour: 8, minute: 0);
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  static String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Strips the "+57" country code the app stores in `phone` so the field
  /// can be edited as a plain 10-digit Colombian mobile number, matching
  /// [PhoneInputField]'s input format on the login screen.
  static String _localPhoneDigits(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  Future<void> _pickTime({required bool isFrom}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isFrom ? _availableFrom : _availableTo,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _availableFrom = picked;
      } else {
        _availableTo = picked;
      }
    });
  }

  void _addCoverageCity() {
    final value = _coverageCityController.text.trim();
    if (value.isEmpty) return;
    final alreadyCovered =
        _coverageCities.any(
          (city) => city.toLowerCase() == value.toLowerCase(),
        ) ||
        value.toLowerCase() == _cityController.text.trim().toLowerCase();
    _coverageCityController.clear();
    if (alreadyCovered) return;
    setState(() => _coverageCities = [..._coverageCities, value]);
  }

  void _removeCoverageCity(String city) {
    setState(
      () => _coverageCities = _coverageCities.where((c) => c != city).toList(),
    );
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar una foto'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final fileExt = picked.path.contains('.')
          ? picked.path.split('.').last
          : 'jpg';
      final photo = await _repository.uploadPhoto(
        bytes: bytes,
        fileExt: fileExt.toLowerCase(),
      );
      if (!mounted) return;
      setState(() => _photos = [photo, ..._photos]);
    } catch (_) {
      if (!mounted) return;
      _showMessage('No pudimos subir la foto. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _deletePhoto(MusicianPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar foto?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _repository.deletePhoto(photo);
      if (!mounted) return;
      setState(() => _photos = _photos.where((p) => p.id != photo.id).toList());
    } catch (_) {
      if (!mounted) return;
      _showMessage('No pudimos eliminar la foto. Intenta de nuevo.');
    }
  }

  /// Combines today's date with the "hasta" time picked in
  /// [AvailabilityTimeCard] into the absolute cutoff stored in
  /// `busy_until`. Rolls over to tomorrow when that time has already
  /// passed today (covers overnight gigs).
  DateTime _computeBusyUntil() {
    final now = DateTime.now();
    var candidate = DateTime(
      now.year,
      now.month,
      now.day,
      _availableTo.hour,
      _availableTo.minute,
    );
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  String? _validate() {
    if (_fullNameController.text.trim().isEmpty) {
      return 'El nombre completo no puede estar vacío.';
    }
    if (_phoneController.text.trim().length != 10) {
      return 'Ingresa un número de WhatsApp válido de 10 dígitos.';
    }
    if (_selectedServices.isEmpty) {
      return 'Selecciona al menos un servicio que ofreces.';
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final validationError = _validate();
    if (validationError != null) {
      _showMessage(validationError);
      return;
    }

    setState(() => _saving = true);
    try {
      final fullName = _fullNameController.text.trim();
      final city = _cityController.text.trim();
      final phone = '+57${_phoneController.text.trim()}';
      final statusMessage = _messageController.text.trim();
      final availabilityNote = _availabilityNoteController.text.trim();
      final serviceDescription = _serviceDescriptionController.text.trim();
      final availableFrom = _formatTime(_availableFrom);
      final availableTo = _formatTime(_availableTo);
      final busyUntil = _isFree ? null : _computeBusyUntil();
      final instruments = _isMusician
          ? _selectedInstruments
          : <String>[];
      final genres = _isMusician ? _selectedGenres : <String>[];

      await Future.wait([
        _repository.updateMusicianStatus(
          isFree: _isFree,
          statusMessage: statusMessage,
          availableFrom: availableFrom,
          availableTo: availableTo,
          availabilityNote: availabilityNote,
          busyUntil: busyUntil,
        ),
        _repository.updateMusicianProfile(
          fullName: fullName,
          instruments: instruments,
          city: city,
          phone: phone,
          genres: genres,
          services: _selectedServices,
          serviceDescription: _hasTechnicalService ? serviceDescription : '',
          coverageCities: _coverageCities,
        ),
      ]);

      if (busyUntil != null) {
        await NotificationService.instance.scheduleBusyUntilNotification(
          busyUntil: busyUntil,
          statusMessage: statusMessage,
        );
      } else {
        await NotificationService.instance.cancelBusyUntilNotification();
      }

      if (!mounted) return;
      setState(() {
        _profile = _profile?.copyWith(
          fullName: fullName,
          instruments: instruments,
          city: city,
          phone: phone,
          genres: genres,
          services: _selectedServices,
          serviceDescription: _hasTechnicalService ? serviceDescription : '',
          coverageCities: _coverageCities,
          isFree: _isFree,
          statusMessage: statusMessage,
          availableFrom: availableFrom,
          availableTo: availableTo,
          availabilityNote: availabilityNote,
          busyUntil: busyUntil,
          clearBusyUntil: busyUntil == null,
        );
      });
      _showMessage('Perfil actualizado correctamente');
    } catch (_) {
      if (!mounted) return;
      _showMessage('No pudimos guardar los cambios. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              )
            : _profile == null
            ? const Center(child: Text('No encontramos tu perfil.'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ],
                  ),
                  Text(
                    'Mi Estado',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Controla tu disponibilidad',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: extension?.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  StatusSwitchCard(
                    isFree: _isFree,
                    onChanged: (value) => setState(() => _isFree = value),
                  ),
                  const SizedBox(height: 16),
                  AvailabilityTimeCard(
                    isFree: _isFree,
                    availabilityNoteController: _availabilityNoteController,
                    from: _availableFrom,
                    to: _availableTo,
                    onPickFrom: () => _pickTime(isFrom: true),
                    onPickTo: () => _pickTime(isFrom: false),
                  ),
                  const SizedBox(height: 16),
                  MessageFieldCard(controller: _messageController),
                  const SizedBox(height: 16),
                  ProfileInfoCard(
                    fullNameController: _fullNameController,
                    cityController: _cityController,
                    phoneController: _phoneController,
                  ),
                  if (_isMusician) ...[
                    const SizedBox(height: 16),
                    MusicianSkillsCard(
                      selectedInstruments: _selectedInstruments,
                      onInstrumentsChanged: (value) =>
                          setState(() => _selectedInstruments = value),
                      selectedGenres: _selectedGenres,
                      onGenresChanged: (value) =>
                          setState(() => _selectedGenres = value),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ServicesCard(
                    selectedServices: _selectedServices,
                    onChanged: (value) =>
                        setState(() => _selectedServices = value),
                  ),
                  if (_hasTechnicalService) ...[
                    const SizedBox(height: 16),
                    ServiceInventoryCard(
                      controller: _serviceDescriptionController,
                    ),
                  ],
                  const SizedBox(height: 16),
                  CoverageCitiesCard(
                    cities: _coverageCities,
                    inputController: _coverageCityController,
                    onAdd: _addCoverageCity,
                    onRemove: _removeCoverageCity,
                  ),
                  const SizedBox(height: 16),
                  GalleryCard(
                    photos: _photos,
                    uploading: _uploadingPhoto,
                    onAddPhoto: _addPhoto,
                    onDeletePhoto: _deletePhoto,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.black,
                                ),
                              ),
                            )
                          : const Text(
                              'Guardar cambios',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Estadísticas',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  StatsPanel(stats: _stats, rating: _profile!.rating),
                ],
              ),
      ),
    );
  }
}
