import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';
import 'widgets/google_sign_in_button.dart';

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
          'Conecta con los mejores músicos,\nagrupaciones y sonido para tu evento.',
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

/// Glassmorphism card: blurred translucent background + the Google
/// Sign-In CTA. `ClipRRect` is required here — without it, `BackdropFilter`
/// blurs a rectangle that ignores the `Container`'s own rounded corners.
class _LoginCard extends StatelessWidget {
  const _LoginCard({required this.isLoading, required this.onGoogleSignIn});

  final bool isLoading;
  final VoidCallback onGoogleSignIn;

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
              GoogleSignInButton(
                isLoading: isLoading,
                onPressed: onGoogleSignIn,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Auto-provisioning note, "Acceso seguro" badge, and the legal disclosure
/// line. The Términos/Política copy is intentionally plain text, not a
/// tappable link: there's no Terms-of-Service/Privacy-Policy destination
/// (screen or URL) yet to send the user to.
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
        Text(
          'Al continuar aceptas los Términos de servicio y la Política de privacidad.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}