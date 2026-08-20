import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart'; // <--- Importante para los enlaces interactivos
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
/// line. Now interactive with professional terms and privacy policy modals.
class _Footer extends StatelessWidget {
  const _Footer();

  void _showLegalModal(BuildContext context, String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121216),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Text(
                    content,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendido'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                  ..onTap = () => _showLegalModal(
                        context,
                        'Términos de Servicio',
                        '1. OBJETO Y NATURALEZA DE LA PLATAFORMA\n\n'
                            'Mussy opera exclusivamente como un directorio digital de intermediación y vitrina comercial. Su finalidad es conectar de manera directa a clientes o organizadores de eventos con prestadores independientes de servicios artísticos, musicales, de animación, DJs y logística de entretenimiento.\n\n'
                            '2. LIMITACIÓN DE RESPONSABILIDAD\n\n'
                            'Mussy no es parte de los contratos de prestación de servicios celebrados entre los usuarios y los artistas o proveedores. Por consiguiente, Mussy no asume ninguna responsabilidad por la calidad, cumplimiento, puntualidad, cancelaciones, pagos o disputas derivadas de las contrataciones acordadas de forma externa a través del contacto facilitado por el directorio.\n\n'
                            '3. USO ADECUADO DE LOS DATOS DE CONTACTO\n\n'
                            'Los números telefónicos y canales de contacto publicados en los perfiles tienen como único propósito propiciar acuerdos comerciales legítimos para eventos. Queda estrictamente prohibido el uso de esta información para fines de suplantación, hostigamiento, campañas masivas de spam o actividades contrarias a la ley colombiana.\n\n'
                            '4. PROPIEDAD INTELECTUAL Y CONTENIDO\n\n'
                            'Los proveedores y artistas garantizan que cuentan con los derechos de autor, autorizaciones e imágenes de perfil expuestas en sus galerías, liberando a Mussy de cualquier reclamación por infracción de derechos de terceros.',
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
                  ..onTap = () => _showLegalModal(
                        context,
                        'Política de Privacidad y Tratamiento de Datos',
                        '1. RESPONSABLE DEL TRATAMIENTO DE DATOS\n\n'
                            'En cumplimiento de la Ley estatutaria 1581 de 2012 y el Decreto reglamentario 1377 de 2013 de Colombia sobre protección de datos personales, informamos que los datos recopilados a través de nuestro sistema de autenticación (nombre, correo electrónico y datos opcionales de perfil o contacto) son tratados bajo rigurosos estándares de seguridad.\n\n'
                            '2. FINALIDAD DE LA RECOLECCIÓN\n\n'
                            'La información suministrada por los usuarios tiene como únicas finalidades:\n'
                            '• Gestionar la creación y autenticación de cuentas de usuario mediante Google.\n'
                            '• Facilitar la visualización del directorio de talento y servicios para eventos.\n'
                            '• Permitir la comunicación directa entre interesados y artistas a través de canales habilitados (como enlaces de WhatsApp).\n\n'
                            '3. NO CESIÓN A TERCEROS\n\n'
                            'Sus datos personales no serán comercializados, cedidos, alquilados ni compartidos con terceros con fines publicitarios o comerciales ajenos a la operación interna de la plataforma.\n\n'
                            '4. DERECHOS DEL TITULAR (HABEAS DATA)\n\n'
                            'Como titular de los datos, usted tiene derecho a conocer, actualizar, rectificar y solicitar la supresión de sus datos personales en cualquier momento, comunicándose directamente con el soporte técnico de Mussy para proceder al retiro de su perfil y registros del sistema.',
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