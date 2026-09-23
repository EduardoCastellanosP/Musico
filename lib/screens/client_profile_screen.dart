import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../models/musician.dart';
import '../repositories/musician_repository.dart';
import '../services/auth_service.dart';
import 'my_bookings_screen.dart';
import 'saved_services_screen.dart';
import 'widgets/legal_modal.dart';
import 'widgets/status/city_picker_sheet.dart';

const _kBackground = Color(0xFF0D0D12);
const _kSurface = Color(0xFF17171D);
const _kInputSurface = Color(0xFF1E1E2C);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

/// The client's own "Perfil" screen: avatar + contact info (name, WhatsApp,
/// default city) required by `isProfileCompleteForBooking`
/// (`core/utils/booking_gate.dart`), plus quick-access rows to the booking
/// flow's future home screens. Reuses [Musician]/[MusicianRepository] —
/// same `profiles` table/columns a musician's own profile uses, just a
/// smaller slice of them.
class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final _repository = MusicianRepository();
  final _authService = AuthService();
  final _imagePicker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  Musician? _profile;
  String _city = 'Bucaramanga';
  bool _loading = true;
  String? _loadError;
  bool _uploadingAvatar = false;
  bool _saving = false;
  bool _deletingAccount = false;

  // Flips true for a couple seconds right after a successful save, so the
  // button can show a check instead of its label — the "animación de
  // éxito" feedback, without a separate confirmation dialog interrupting
  // the flow.
  bool _justSaved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final profile = await _repository.fetchCurrentProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _nameController.text = profile?.fullName ?? '';
        _phoneController.text = profile == null ? '' : _localPhoneDigits(profile.phone);
        _city = (profile?.city.trim().isNotEmpty ?? false) ? profile!.city : 'Bucaramanga';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  /// Strips the "+57" country code so the field edits as a plain 10-digit
  /// number — same convention `StatusScreen` uses for a musician's own
  /// phone field.
  static String _localPhoneDigits(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAvatar() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await image.readAsBytes();
      final fileExt = image.path.contains('.') ? image.path.split('.').last : 'jpg';
      final avatarUrl = await _repository.updateAvatar(
        bytes: bytes,
        fileExt: fileExt.toLowerCase(),
      );
      if (!mounted) return;
      setState(() {
        _profile = _profile?.copyWith(avatarUrl: avatarUrl);
        _uploadingAvatar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingAvatar = false);
      _showMessage('No pudimos actualizar tu foto: $e');
    }
  }

  Future<void> _pickCity() async {
    final picked = await showCityPickerSheet(context, title: 'Tu ciudad predeterminada');
    if (picked != null) setState(() => _city = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = _profile;
    if (profile == null) return;

    final phoneDigits = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final phone = '+57$phoneDigits';

    setState(() => _saving = true);
    try {
      if (await _repository.isPhoneTaken(phone, excludingId: profile.id)) {
        if (!mounted) return;
        setState(() => _saving = false);
        _showMessage('Ese número de WhatsApp ya está registrado en otra cuenta.');
        return;
      }

      final fullName = _nameController.text.trim();
      await _repository.updateClientContactInfo(
        fullName: fullName,
        phone: phone,
        city: _city,
      );

      if (!mounted) return;
      setState(() {
        _profile = profile.copyWith(fullName: fullName, phone: phone, city: _city);
        _saving = false;
        _justSaved = true;
      });
      _showMessage('Perfil actualizado.');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _justSaved = false);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('No se pudo guardar tu perfil: $e');
    }
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

    // `AuthGate` reacts to the session clearing and swaps its own content
    // to `LoginScreen` — but unlike `AdminDashboardScreen` (which *is*
    // AuthGate's content directly), this screen is reached via
    // `Navigator.push` from `ClientHomeScreen`'s bottom bar, so it's a
    // route sitting on top of AuthGate's. Popping back to that root route
    // is what actually makes the now-updated content visible again —
    // without it, AuthGate swaps underneath while this screen keeps
    // covering it, and "Cerrar sesión" looks like it does nothing.
    try {
      await _authService.signOut();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      _showMessage('No se pudo cerrar sesión: $e');
    }
  }

  /// "Eliminar mi cuenta": same irreversible-deletion flow as a musician's
  /// own profile (`StatusScreen._confirmDeleteAccount`) — confirms via
  /// [AlertDialog], then wipes Storage files and the `auth.users` row via
  /// [MusicianRepository.deleteAccount], and pops back to `AuthGate`'s
  /// route so it can react to the cleared session.
  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar tu cuenta?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Esta acción es irreversible: se borrarán tu perfil, tus reservas '
          'y tu historial de forma permanente.',
          style: TextStyle(color: _kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar', style: TextStyle(color: _kTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
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
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      _showMessage('No pudimos eliminar tu cuenta: $e');
    }
  }

  void _showLegalOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined, color: _kAccent),
              title: const Text('Términos de servicio', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                showLegalModal(context, title: 'Términos de Servicio', content: kTermsOfServiceText);
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined, color: _kAccent),
              title: const Text(
                'Política de privacidad',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                showLegalModal(
                  context,
                  title: 'Política de Privacidad y Tratamiento de Datos',
                  content: kPrivacyPolicyText,
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark,
      child: Scaffold(
        backgroundColor: _kBackground,
        appBar: AppBar(
          backgroundColor: _kBackground,
          elevation: 0,
          title: const Text('Mi perfil', style: TextStyle(color: Colors.white)),
        ),
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No se pudo cargar tu perfil.\n$_loadError',
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

    final email = Supabase.instance.client.auth.currentUser?.email ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _ProfileHeader(
          avatarUrl: _profile?.avatarUrl,
          email: email,
          uploading: _uploadingAvatar,
          onTapCamera: _pickAvatar,
          nameField: TextFormField(
            controller: _nameController,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Tu nombre completo',
              hintStyle: TextStyle(color: _kTextSecondary),
              isDense: true,
            ),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? 'Ingresa tu nombre' : null,
          ),
        ),
        const SizedBox(height: 28),
        _GlassCard(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('Datos de contacto'),
                const SizedBox(height: 14),
                _FieldLabel('Teléfono / WhatsApp'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration(hint: '300 123 4567', icon: Icons.chat_rounded)
                      .copyWith(
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 16, right: 8),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          '🇨🇴 +57',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  ),
                  validator: (value) {
                    final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.isEmpty) return 'Ingresa tu número de WhatsApp';
                    if (digits.length < 10) return 'Debe tener 10 dígitos';
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                _FieldLabel('Ciudad predeterminada'),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _pickCity,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _kInputSurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: _kAccent, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_city, style: const TextStyle(color: Colors.white)),
                        ),
                        const Icon(Icons.keyboard_arrow_right_rounded, color: _kTextSecondary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _justSaved ? Colors.green.shade600 : _kAccent,
                      foregroundColor: _justSaved ? Colors.white : Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _saving
                          ? const SizedBox(
                              key: ValueKey('saving'),
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : _justSaved
                              ? const Row(
                                  key: ValueKey('saved'),
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle_rounded),
                                    SizedBox(width: 8),
                                    Text('Guardado', style: TextStyle(fontWeight: FontWeight.w700)),
                                  ],
                                )
                              : const Text(
                                  key: ValueKey('idle'),
                                  'Guardar cambios',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _ProfileMenuTile(
                icon: Icons.event_note_rounded,
                title: 'Mis reservas / eventos',
                subtitle: 'Consulta el estado de tus solicitudes',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
                ),
              ),
              const _MenuDivider(),
              _ProfileMenuTile(
                icon: Icons.favorite_rounded,
                title: 'Artistas guardados',
                subtitle: 'Tu lista de favoritos',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SavedServicesScreen()),
                ),
              ),
              const _MenuDivider(),
              _ProfileMenuTile(
                icon: Icons.description_outlined,
                title: 'Términos y políticas de privacidad',
                onTap: _showLegalOptions,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _confirmSignOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar sesión', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: _deletingAccount ? null : _confirmDeleteAccount,
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _deletingAccount
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text(
              'Eliminar mi cuenta',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _kTextSecondary),
      filled: true,
      fillColor: _kInputSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.avatarUrl,
    required this.email,
    required this.uploading,
    required this.onTapCamera,
    required this.nameField,
  });

  final String? avatarUrl;
  final String email;
  final bool uploading;
  final VoidCallback onTapCamera;
  final Widget nameField;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(BorderSide(color: _kAccent, width: 3)),
              ),
              child: CircleAvatar(
                radius: 50,
                backgroundColor: _kSurface,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                child: avatarUrl == null
                    ? const Icon(Icons.person, size: 44, color: _kTextSecondary)
                    : null,
              ),
            ),
            Positioned(
              bottom: -2,
              right: -2,
              child: GestureDetector(
                onTap: uploading ? null : onTapCamera,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _kAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: _kBackground, width: 3),
                  ),
                  child: uploading
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.camera_alt_rounded, color: Colors.black, size: 18),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        nameField,
        const SizedBox(height: 4),
        Text(email, style: const TextStyle(color: _kTextSecondary, fontSize: 13)),
      ],
    );
  }
}

/// Frosted, subtly translucent card used for every section on this
/// screen — the "glassmorphism" surfaces the design brief asked for.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: _kTextSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13));
  }
}

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: _kAccent, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(color: _kTextSecondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_right_rounded, color: _kTextSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: Colors.white.withValues(alpha: 0.08), indent: 18, endIndent: 18);
  }
}
