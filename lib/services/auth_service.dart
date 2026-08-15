import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps the Supabase Auth calls needed by the login flow so the UI layer
/// never touches the Supabase SDK directly.
class AuthService {
  AuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Starts the Google OAuth flow through Supabase.
  ///
  /// This is the only sign-in path the app supports: phone/SMS auth isn't
  /// enabled on the Supabase project (no SMS provider configured), so
  /// `signInWithOtp` would fail with "Unsupported phone provider".
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.vallenatoconnect://login-callback',
    );
  }

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signOut() => _client.auth.signOut();
}
