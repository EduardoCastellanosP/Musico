import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart'; // <--- Importante para los enlaces interactivos
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';
import 'widgets/google_sign_in_button.dart';
import 'widgets/legal_modal.dart';

/// Pre-auth landing screen: a looping, muted video background behind a
/// glassmorphism Google Sign-In card. Deliberately theme-locked to dark
/// (see [build]) — the video/overlay design doesn't adapt to the app's
/// light/dark toggle, so descendants that read the ambient [Theme] (like
/// [GoogleSignInButton]) would otherwise render unreadable dark-on-dark
/// text whenever the device's last selected app theme was light.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _backgroundVideoAsset = 'assets/videos/videoluces.mp4';

  final AuthService _authService = AuthService();
  final _passwordFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final VideoPlayerController _videoController;
  bool _isLoading = false;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset(_backgroundVideoAsset);
    unawaited(_initVideoPlayer());
  }

  /// Initializes the background video defensively: every step past
  /// `initialize()` re-checks [mounted] before touching state or the
  /// controller, since the widget can be disposed mid-await (fast
  /// navigation away, hot restart) and `video_player` throws if a disposed
  /// controller is used afterwards. Any failure (missing/corrupt asset,
  /// unsupported codec) is swallowed here — [build] falls back to a static
  /// gradient whenever `_isVideoInitialized` never flips true.
  Future<void> _initVideoPlayer() async {
    try {
      await _videoController.initialize();
      if (!mounted) return;

      await _videoController.setLooping(true);
      await _videoController.setVolume(0.0);
      if (!mounted) return;

      setState(() => _isVideoInitialized = true);
      unawaited(_videoController.play());
    } catch (error) {
      debugPrint('Error al inicializar el video de fondo: $error');
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await _authService.signInWithGoogle();
    } on AuthException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage('No pudimos iniciar sesión con Google.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePasswordSignIn() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await _authService.signInWithPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );
    } on AuthException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage('No pudimos iniciar sesión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// `true` only once every dimension needed to lay the video out safely is
  /// known — guards against the brief window (seen on some Android
  /// decoders) where `isInitialized` flips true a frame before `value.size`
  /// is populated, which would hand `FittedBox` a zero-sized child and risk
  /// a "Cannot hit test a render box that has never been laid out" failure.
  bool get _canRenderVideo {
    if (!_isVideoInitialized || !_videoController.value.isInitialized) {
      return false;
    }
    final size = _videoController.value.size;
    return size.width > 0 && size.height > 0;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight = mediaQuery.size.height - mediaQuery.padding.top - mediaQuery.padding.bottom - 48;

    return Theme(
      data: AppTheme.dark,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: _canRenderVideo
                  ? SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _videoController.value.size.width,
                          height: _videoController.value.size.height,
                          child: VideoPlayer(_videoController),
                        ),
                      ),
                    )
                  : const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1C1630), Color(0xFF0B0B0E)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: availableHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(height: 20),
                      const _Hero(),
                      const SizedBox(height: 32),
                      _LoginCard(
                        isLoading: _isLoading,
                        onGoogleSignIn: _handleGoogleSignIn,
                        formKey: _passwordFormKey,
                        emailController: _emailController,
                        passwordController: _passwordController,
                        onPasswordSignIn: _handlePasswordSignIn,
                      ),
                      const SizedBox(height: 32),
                      const _Footer(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Isotipo + "MUSSY" wordmark + one-line pitch.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: const Center(
            child: Text(
              'M',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'MUSSY',
          style: TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Encuentra músicos, agrupaciones, DJs, animadores y\n servicios profesionales para tu evento.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

/// Glassmorphism card: blurred translucent background, the email/password
/// form, and the Google Sign-In CTA below it. `ClipRRect` is required here
/// — without it, `BackdropFilter` blurs a rectangle that ignores the
/// `Container`'s own rounded corners.
class _LoginCard extends StatefulWidget {
  const _LoginCard({
    required this.isLoading,
    required this.onGoogleSignIn,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.onPasswordSignIn,
  });

  final bool isLoading;
  final VoidCallback onGoogleSignIn;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final VoidCallback onPasswordSignIn;

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool _obscurePassword = true;
  bool _emailLooksValid = false;

  InputDecoration _fieldDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
      prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.6)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              Text(
                'Inicia sesión para continuar',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 20),
              Form(
                key: widget.formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  children: [
                    TextFormField(
                      controller: widget.emailController,
                      enabled: !widget.isLoading,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      style: const TextStyle(color: Colors.white),
                      onChanged: (value) => setState(
                        () => _emailLooksValid = _emailRegex.hasMatch(value.trim()),
                      ),
                      decoration: _fieldDecoration('Correo', Icons.email_outlined).copyWith(
                        suffixIcon: _emailLooksValid
                            ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                            : null,
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Ingresa tu correo';
                        if (!_emailRegex.hasMatch(email)) {
                          return 'Correo inválido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: widget.passwordController,
                      enabled: !widget.isLoading,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.password],
                      style: const TextStyle(color: Colors.white),
                      decoration: _fieldDecoration('Contraseña', Icons.lock_outline).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) => (value == null || value.length < 6)
                          ? 'Mínimo 6 caracteres'
                          : null,
                      onFieldSubmitted: (_) =>
                          widget.isLoading ? null : widget.onPasswordSignIn(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: widget.isLoading ? null : widget.onPasswordSignIn,
                        child: widget.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Iniciar sesión'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.15))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'o',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.15))),
                ],
              ),
              const SizedBox(height: 20),
              GoogleSignInButton(
                isLoading: widget.isLoading,
                onPressed: widget.onGoogleSignIn,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Auto-provisioning note, "Acceso seguro" badge, and the legal disclosure
/// line. Now interactive with professional terms and privacy policy modals.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Si eres nuevo, tu cuenta se crea automáticamente.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 12, color: Colors.white70),
              const SizedBox(width: 6),
              const Text(
                'Acceso seguro',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
            children: [
              const TextSpan(text: 'Al continuar aceptas los '),
              TextSpan(
                text: 'Términos de servicio',
                style: const TextStyle(
                  color: Colors.white, // Blanco destacado
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => showLegalModal(
                        context,
                        title: 'Términos de Servicio',
                        content: kTermsOfServiceText,
                      ),
              ),
              const TextSpan(text: ' y la '),
              TextSpan(
                text: 'Política de privacidad',
                style: const TextStyle(
                  color: Colors.white, // Blanco destacado
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => showLegalModal(
                        context,
                        title: 'Política de Privacidad y Tratamiento de Datos',
                        content: kPrivacyPolicyText,
                      ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
      ],
    );
  }
}