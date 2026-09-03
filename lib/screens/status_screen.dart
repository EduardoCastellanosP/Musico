import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/media_limits.dart';
import '../core/constants/services.dart';
import '../core/theme/app_theme.dart';
import '../models/musician.dart';
import '../models/musician_stats.dart';
import '../models/musician_video.dart';
import '../repositories/musician_repository.dart';
import '../services/auth_service.dart';
// ponytail: NotificationService desconectado para v1, ver _save().
// import '../services/notification_service.dart';
// ponytail: selector de franja horaria oculto para v1, ver build().
// import 'widgets/status/availability_time_card.dart';
import 'widgets/status/coverage_cities_card.dart';
import 'widgets/status/media_manager_card.dart';
import 'widgets/status/message_field_card.dart';
import 'widgets/status/musician_skills_card.dart';
import 'profile_preview_screen.dart';
import 'widgets/profile/profile_header.dart';
import 'widgets/status/profile_info_card.dart';
import 'widgets/status/service_inventory_card.dart';
import 'widgets/status/services_card.dart';
import 'widgets/status/stats_panel.dart';
import 'widgets/status/status_switch_card.dart';
import 'auth_gate.dart';

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
  final AuthService _authService = AuthService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _experienceYearsController =
      TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _availabilityNoteController =
      TextEditingController();
  final TextEditingController _serviceDescriptionController =
      TextEditingController();

  Musician? _profile;
  MusicianStats _stats = MusicianStats.zero;
  List<String> _photos = [];
  List<MusicianVideo> _videos = [];
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
  bool _uploadingVideo = false;
  bool _uploadingAvatar = false;
  bool _uploadingCover = false;
  bool _deletingAccount = false;
  bool _signingOut = false;

  bool get _isMusician => _selectedServices.contains(MusicianServices.musician);

  bool get _hasTechnicalService =>
      _selectedServices.any(MusicianServices.technical.contains);

  /// Same branching [Musician.descriptionSectionTitle] uses, computed from
  /// the form's *unsaved* selection instead of the last-saved [_profile] —
  /// keeps the title in sync as the user checks/unchecks services, before
  /// they've hit "Guardar cambios".
  String get _descriptionTitle {
    if (_isMusician && _hasTechnicalService) return 'Experiencia y equipo que ofrece';
    if (_isMusician) return 'Experiencia';
    if (_hasTechnicalService) return 'Inventario y equipo';
    return 'Descripción';
  }

  String get _descriptionHint {
    if (_isMusician && _hasTechnicalService) {
      return 'Ej: 8 años tocando acordeón en bandas vallenatas, más consola '
          'de 12 canales y cabinas propias para eventos pequeños.';
    }
    if (_isMusician) {
      return 'Ej: 8 años de experiencia, bandas con las que has tocado, '
          'festivales o eventos destacados.';
    }
    if (_hasTechnicalService) {
      return 'Ej: 2 cabinas activas de 15", consola de 12 canales, '
          'micrófonos inalámbricos. Sala insonorizada con batería, '
          'bajo y teclado incluidos.';
    }
    return 'Cuéntale a los contratantes qué ofreces.';
  }

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
    _experienceYearsController.dispose();
    _phoneController.dispose();
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

    final stats = await _repository.fetchContactStats(profile.id);

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _stats = stats;
      _photos = List<String>.from(profile.photos);
      _videos = List<MusicianVideo>.from(profile.videos);
      _isFree = profile.isFree;
      _messageController.text = profile.statusMessage;
      _fullNameController.text = profile.fullName;
      _cityController.text = profile.city;
      _experienceYearsController.text = profile.experienceYears.toString();
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

  // ponytail: selector de franja horaria oculto para v1 → _pickTime,
  // eliminado por no tener llamadores; restaurar junto con AvailabilityTimeCard.

  void _addCoverageCity(String city) {
    final value = city.trim();
    if (value.isEmpty) return;
    final alreadyCovered =
        _coverageCities.any(
          (covered) => covered.toLowerCase() == value.toLowerCase(),
        ) ||
        value.toLowerCase() == _cityController.text.trim().toLowerCase();
    if (alreadyCovered) return;
    setState(() => _coverageCities = [..._coverageCities, value]);
  }

  /// v1: el switch Libre/Ocupado ya no espera al botón "Guardar cambios" —
  /// escribe en Supabase al instante (optimista, con rollback si falla),
  /// igual que el switch del dashboard.
  Future<void> _toggleAvailability(bool isFree) async {
    final previous = _isFree;
    setState(() => _isFree = isFree);
    try {
      await _repository.setAvailability(isFree);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFree = previous);
      _showMessage('No pudimos actualizar tu disponibilidad. Intenta de nuevo.');
    }
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
      final photoUrl = await _repository.addPhoto(
        bytes: bytes,
        fileExt: fileExt.toLowerCase(),
      );
      if (!mounted) return;
      setState(() => _photos = [..._photos, photoUrl]);
    } catch (error) {
      if (!mounted) return;
      _showMessage('No pudimos subir la foto: $error');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _updateProfilePicture() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await image.readAsBytes();
      final fileExt = image.path.contains('.')
          ? image.path.split('.').last
          : 'jpg';
      final avatarUrl = await _repository.updateAvatar(
        bytes: bytes,
        fileExt: fileExt.toLowerCase(),
      );
      if (!mounted) return;
      setState(() {
        _profile = _profile?.copyWith(avatarUrl: avatarUrl);
      });
    } catch (error) {
      if (!mounted) return;
      _showMessage('No pudimos actualizar tu foto de perfil: $error');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  /// Same pick/upload shape as [_updateProfilePicture], for the header's
  /// background photo ([ProfileHeader.backgroundImageUrl]) instead of the
  /// avatar. Offers gallery or camera, matching [_addPhoto]'s source sheet.
  Future<void> _updateCoverPhoto() async {
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

    final image = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() => _uploadingCover = true);
    try {
      final bytes = await image.readAsBytes();
      final fileExt = image.path.contains('.')
          ? image.path.split('.').last
          : 'jpg';
      final coverUrl = await _repository.updateCover(
        bytes: bytes,
        fileExt: fileExt.toLowerCase(),
      );
      if (!mounted) return;
      setState(() {
        _profile = _profile?.copyWith(coverUrl: coverUrl);
      });
    } catch (error) {
      if (!mounted) return;
      _showMessage('No pudimos actualizar tu foto de fondo: $error');
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _removePhoto(String url) async {
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
      await _repository.removePhoto(url);
      if (!mounted) return;
      setState(() => _photos = _photos.where((p) => p != url).toList());
    } catch (_) {
      if (!mounted) return;
      _showMessage('No pudimos eliminar la foto. Intenta de nuevo.');
    }
  }

  /// Picks a local video, compresses it on-device (`video_compress`), then
  /// uploads the compressed file — mirrors [_addPhoto]'s pick/upload shape,
  /// with a compression pass in between. `VideoCompress.deleteAllCache()`
  /// in `finally` keeps the compressed temp file from lingering on disk
  /// after the upload finishes (success or not).
  Future<void> _addVideo() async {
    final XFile? picked = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
    );
    if (picked == null) return;

    final maxSeconds = MediaLimits.maxVideoDuration.inSeconds;
    try {
      final info = await VideoCompress.getMediaInfo(picked.path);
      final durationInSeconds = (info.duration ?? 0) / 1000;

      if (durationInSeconds > maxSeconds) {
        _showMessage(
          'El video es muy largo. Tiene que ser de máximo ${maxSeconds ~/ 60} minutos.',
        );
        return;
      }
    } catch (_) {
      // Si por alguna razón no se puede leer la info, dejamos continuar o manejamos el error
    }

    setState(() => _uploadingVideo = true);
    _showMessage('Comprimiendo video, esto puede tardar un momento...');
    try {
      final info = await VideoCompress.compressVideo(
        picked.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );
      final compressedFile = info?.file;
      if (compressedFile == null) {
        throw StateError('No pudimos comprimir el video.');
      }

      _showMessage('Subiendo video...');
      final bytes = await compressedFile.readAsBytes();
      final fileExt = picked.path.contains('.')
          ? picked.path.split('.').last
          : 'mp4';
      final video = await _repository.addVideo(
        bytes: bytes,
        fileExt: fileExt.toLowerCase(),
      );
      if (!mounted) return;
      setState(() => _videos = [..._videos, video]);
      _showMessage('Video agregado correctamente');
    } catch (error) {
      if (!mounted) return;
      _showMessage('No pudimos agregar el video: $error');
    } finally {
      await VideoCompress.deleteAllCache();
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _removeVideo(MusicianVideo video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar video?'),
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
      await _repository.removeVideo(video);
      if (!mounted) return;
      setState(() => _videos = _videos.where((v) => v.id != video.id).toList());
    } catch (_) {
      if (!mounted) return;
      _showMessage('No pudimos eliminar el video. Intenta de nuevo.');
    }
  }

  /// "Cerrar sesión": clears the local Supabase session, then replaces the
  /// entire navigation stack with a fresh [AuthGate] — [Navigator
  /// .pushAndRemoveUntil] with `(route) => false` drops every pushed route
  /// (including this one, and the original `AuthGate` the app started on),
  /// so the physical back button can't return to a screen backed by a
  /// session that no longer exists. Pushing [AuthGate] rather than
  /// [LoginScreen] directly matters: `AuthGate` is what subscribes to
  /// `onAuthStateChange`, so a bare `LoginScreen` here would leave nothing
  /// listening for the *next* successful sign-in, stranding the user on
  /// the login screen even after Supabase reports SIGNED_IN.
  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Podrás volver a iniciar sesión cuando quieras.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _signingOut = true);
    try {
      await _authService.signOut();
    } catch (_) {
      // The local session is cleared by the SDK even if the remote
      // sign-out call fails (e.g. offline) — proceed to LoginScreen either
      // way, same rationale as _confirmDeleteAccount's sign-out fallback.
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  /// "Eliminar cuenta": confirms via [AlertDialog], then wipes Storage
  /// files, the `auth.users` row (which cascades to every related table —
  /// see [MusicianRepository.deleteAccount]) and finally the local session.
  /// No manual navigation to [LoginScreen] is needed: [AuthGate] reacts to
  /// the auth-state change and swaps screens on its own.
  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar tu cuenta?'),
        content: const Text(
          'Esta acción es irreversible: se borrarán tu perfil, tu galería '
          'de fotos y todo tu historial de contactos de forma permanente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deletingAccount = true);
    try {
      await _repository.deleteAccount();
      try {
        await _authService.signOut();
      } catch (_) {
        // The account is already gone server-side either way; a failed
        // remote sign-out call doesn't stop the local session from having
        // been cleared, which is what AuthGate reacts to.
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      _showMessage('No pudimos eliminar tu cuenta. Intenta de nuevo.');
    }
  }

  // ponytail: selector de franja horaria oculto para v1 → _computeBusyUntil,
  // eliminado por no tener llamadores; restaurar junto con AvailabilityTimeCard.

  /// Blocks "Guardar cambios" until every mandatory field is filled in —
  /// this is the only place completeness is enforced (write-time, purely
  /// client-side); the directory's `SELECT` stays open to every profile
  /// regardless of this, see `schema.sql` section 13. Each check returns a
  /// single, specific message naming exactly what's missing. The same 5
  /// fields back [Musician.hasCompleteProfile], used separately to gate
  /// *contacting* someone else.
  String? _validate() {
    if (_fullNameController.text.trim().isEmpty) {
      return 'El nombre completo no puede estar vacío.';
    }
    if (_cityController.text.trim().isEmpty) {
      return 'Ingresa tu ciudad para poder publicar tu perfil.';
    }
    final phoneDigits = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneDigits.length != 10) {
      return 'Ingresa un número de WhatsApp válido de 10 dígitos.';
    }
    if (_selectedServices.isEmpty) {
      return 'Selecciona al menos un instrumento o servicio que ofreces.';
    }
    if (_isMusician && _selectedInstruments.isEmpty) {
      return 'Selecciona al menos un instrumento que toques.';
    }
    final experienceYears = int.tryParse(_experienceYearsController.text.trim());
    if (experienceYears == null || experienceYears < 0) {
      return 'Ingresa un número válido de años de experiencia.';
    }
    if (_photos.isEmpty) {
      return 'Sube al menos 1 foto para poder publicar tu perfil.';
    }
    if (_videos.isEmpty) {
      return 'Sube al menos 1 video para poder publicar tu perfil.';
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
      final experienceYears =
          int.parse(_experienceYearsController.text.trim());
      final phoneDigits = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
      final phone = '+57$phoneDigits';

      if (await _repository.isPhoneTaken(phone, excludingId: _profile!.id)) {
        if (!mounted) return;
        setState(() => _saving = false);
        _showMessage('Este número de WhatsApp ya está registrado en otro perfil.');
        return;
      }

      final statusMessage = _messageController.text.trim();
      final availabilityNote = _availabilityNoteController.text.trim();
      final serviceDescription = _serviceDescriptionController.text.trim();
      final availableFrom = _formatTime(_availableFrom);
      final availableTo = _formatTime(_availableTo);
      // ponytail: franja horaria oculta para v1 — el switch ya escribió
      // is_free al instante, así que aquí solo se preserva busy_until.
      final busyUntil = _isFree ? null : _profile?.busyUntil;
      final instruments = _isMusician ? _selectedInstruments : <String>[];
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
          experienceYears: experienceYears,
          phone: phone,
          genres: genres,
          services: _selectedServices,
          serviceDescription: serviceDescription,
          coverageCities: _coverageCities,
        ),
      ]);

      // ponytail: NotificationService desconectado para v1 — sin
      // programación automática de notificaciones de "ocupado hasta".
      // if (busyUntil != null) {
      //   await NotificationService.instance.scheduleBusyUntilNotification(
      //     busyUntil: busyUntil,
      //     statusMessage: statusMessage,
      //   );
      // } else {
      //   await NotificationService.instance.cancelBusyUntilNotification();
      // }

      if (!mounted) return;
      setState(() {
        _profile = _profile?.copyWith(
          fullName: fullName,
          instruments: instruments,
          city: city,
          experienceYears: experienceYears,
          phone: phone,
          genres: genres,
          services: _selectedServices,
          serviceDescription: serviceDescription,
          coverageCities: _coverageCities,
          isFree: _isFree,
          statusMessage: statusMessage,
          availableFrom: availableFrom,
          availableTo: availableTo,
          availabilityNote: availabilityNote,
          busyUntil: busyUntil,
          clearBusyUntil: busyUntil == null,
        );
        _saving = false;
      });
      await _showSavedDialogThenGoHome();
    } catch (_) {
      if (!mounted) return;
      _showMessage('No pudimos guardar los cambios. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Success modal for a save — SweetAlert-style: rounded, centered, a soft
  /// scale-in, no dismiss but the "Continuar" button. Once the user taps
  /// it, [Navigator.popUntil] with `isFirst` drops every route pushed on
  /// top of the app's root screen (this form included), the unnamed
  /// equivalent of `pushNamedAndRemoveUntil` — this app never registered
  /// named routes (see `MyApp.home` in `main.dart`), and matches the same
  /// "can't come back to a stale screen" pattern [_confirmSignOut] already
  /// uses via `pushAndRemoveUntil`.
  Future<void> _showSavedDialogThenGoHome() async {
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Perfil guardado',
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, _, _) => const _SavedSuccessDialog(),
      transitionBuilder: (context, animation, _, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        return Opacity(
          opacity: animation.value.clamp(0, 1),
          child: Transform.scale(scale: 0.85 + 0.15 * curve.value, child: child),
        );
      },
    );
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return Scaffold(
      bottomNavigationBar: (_loading || _profile == null)
          ? null
          : _SaveBar(saving: _saving, onSave: _save),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.profileAccent,
                ),
              )
            : _profile == null
            ? const Center(child: Text('No encontramos tu perfil.'))
            : ListView(
                // Keyed so the scroll offset survives rebuilds triggered by
                // picking a photo/video (image_picker backgrounds the app
                // briefly, and the ensuing setState calls would otherwise
                // reset the Scrollable to a fresh position).
                key: const PageStorageKey('status_screen_list'),
                // Extra bottom padding keeps the last cards (Galería,
                // Estadísticas) from ending up hidden behind the floating
                // `_SaveBar` once the user scrolls all the way down.
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Ver cómo luce mi perfil',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ProfilePreviewScreen(musician: _profile!),
                          ),
                        ),
                        icon: const Icon(Icons.visibility_outlined),
                      ),
                    ],
                  ),
                  // Doubles as a live preview of the public profile
                  // ([MusicianDetailScreen] renders the exact same
                  // [ProfileHeader]) — with the cover/avatar edit
                  // affordances wired in here, since this is the only
                  // screen where editing your own profile makes sense.
                  ProfileHeader(
                    musician: _profile!,
                    backgroundImageUrl: _profile!.coverUrl,
                    onEditCover: _updateCoverPhoto,
                    uploadingCover: _uploadingCover,
                    onEditAvatar: _updateProfilePicture,
                    uploadingAvatar: _uploadingAvatar,
                  ),
                  const SizedBox(height: 16),
                  ProfileInfoCard(
                    fullNameController: _fullNameController,
                    cityController: _cityController,
                    experienceYearsController: _experienceYearsController,
                    phoneController: _phoneController,
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
                    onChanged: _toggleAvailability,
                  ),
                  // ponytail: franja horaria / "ocupado hasta" oculta para v1.
                  // const SizedBox(height: 16),
                  // AvailabilityTimeCard(
                  //   isFree: _isFree,
                  //   availabilityNoteController: _availabilityNoteController,
                  //   from: _availableFrom,
                  //   to: _availableTo,
                  //   onPickFrom: () => _pickTime(isFrom: true),
                  //   onPickTo: () => _pickTime(isFrom: false),
                  // ),
                  const SizedBox(height: 16),
                  MessageFieldCard(controller: _messageController),
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
                  const SizedBox(height: 16),
                  ServiceInventoryCard(
                    controller: _serviceDescriptionController,
                    title: _descriptionTitle,
                    hint: _descriptionHint,
                  ),
                  const SizedBox(height: 16),
                  CoverageCitiesCard(
                    cities: _coverageCities,
                    onAddCity: _addCoverageCity,
                    onRemove: _removeCoverageCity,
                  ),
                  const SizedBox(height: 16),
                  MediaManagerCard(
                    photos: _photos,
                    videos: _videos,
                    uploadingPhoto: _uploadingPhoto,
                    uploadingVideo: _uploadingVideo,
                    onAddPhoto: _addPhoto,
                    onRemovePhoto: _removePhoto,
                    onAddVideo: _addVideo,
                    onRemoveVideo: _removeVideo,
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
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _signingOut ? null : _confirmSignOut,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: _signingOut
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : const Icon(Icons.logout_rounded),
                      label: const Text(
                        'Cerrar sesión',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Zona de peligro',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Esta acción no se puede deshacer.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: extension?.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _deletingAccount
                          ? null
                          : _confirmDeleteAccount,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: _deletingAccount
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.red,
                              ),
                            )
                          : const Icon(Icons.delete_forever_rounded),
                      label: const Text(
                        'Eliminar cuenta',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "Guardar cambios" as a frosted-glass bar pinned to the bottom of the
/// screen (via [Scaffold.bottomNavigationBar]) instead of scrolling away
/// with the form — it stays reachable no matter how long the profile gets.
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.saving, required this.onSave});

  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottomInset),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xE6121212)
                : Colors.white.withValues(alpha: 0.85),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? const Color(0xFF27272A)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: saving ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.profileAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
        ),
      ),
    );
  }
}

/// SweetAlert-style success modal shown after a profile save — rounded
/// card, a glowing checkmark, and a single "Continuar" action. Purely
/// presentational: [StatusScreen._showSavedDialogThenGoHome] owns the
/// entrance animation and what happens once this pops itself.
class _SavedSuccessDialog extends StatelessWidget {
  const _SavedSuccessDialog();

  static const _success = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppThemeExtension>();

    return Dialog(
      backgroundColor: extension?.cardColor ?? theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _success.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: _success.withValues(alpha: 0.25),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                color: _success,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '¡Datos guardados con éxito!',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tu perfil está listo para que los organizadores te encuentren.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: extension?.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: _success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Continuar',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}