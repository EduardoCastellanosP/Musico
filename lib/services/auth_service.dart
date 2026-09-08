import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps the Supabase Auth calls needed by the login flow so the UI layer
/// never touches the Supabase SDK directly.
/// 
/// Implementa principios de arquitectura limpia y encapsulamiento de seguridad
/// para la gestión de tokens y sesiones OAuth con Google.
class AuthService {
  AuthService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Starts the Google OAuth flow through Supabase.
  ///
  /// Utiliza un esquema de deep link personalizado (`io.supabase.vallenatoconnect://login-callback`)
  /// para retornar de forma segura desde el navegador externo nativo hacia la aplicación móvil.
  /// 
  /// Lanza una excepción controlada en caso de fallo en la red o en el proveedor de identidad.
  Future<bool> signInWithGoogle() async {
  try {
    final response = await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'mussy://login-callback',
      authScreenLaunchMode: LaunchMode.externalApplication,
    );

    debugPrint('GOOGLE OAUTH RESPONSE: $response');

    return response;
  } on AuthException catch (e, stack) {
    // Supabase rejected the request itself (bad provider config, redirect
    // URL not in the allow-list, disabled provider, etc).
    debugPrint(
      'SUPABASE AUTH ERROR: message="${e.message}" statusCode=${e.statusCode} code=${e.code}',
    );
    debugPrint('$stack');
    rethrow;
  } on PlatformException catch (e, stack) {
    // Thrown by the underlying Android/url_launcher plugin before Supabase
    // even gets involved, e.g. no browser/Custom Tabs provider available.
    debugPrint(
      'PLATFORM EXCEPTION: code=${e.code} message="${e.message}" details=${e.details}',
    );
    debugPrint('$stack');
    rethrow;
  } catch (e, stack) {
    debugPrint('GOOGLE LOGIN ERROR (unknown): $e');
    debugPrint('$stack');
    rethrow;
  }
}

  /// Retorna la sesión activa actual almacenada de forma segura en el dispositivo.
  Session? get currentSession => _client.auth.currentSession;

  /// Stream reactivo para escuchar cambios en el ciclo de vida de la autenticación
  /// (Login, Logout, Token Refreshed). Vital para el funcionamiento del AuthGate.
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Cierra la sesión activa de forma segura y limpia los registros locales cifrados.
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      rethrow;
    }
  }
}