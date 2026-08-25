import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dashboard_screen.dart';
import 'login_screen.dart';

/// Root routing widget: shows [DashboardScreen] while a Supabase session is
/// active, [LoginScreen] otherwise. Rebuilds instantly on every auth change
/// (OTP verification, Google OAuth callback, sign-out) via
/// [GoTrueClient.onAuthStateChange], so no manual navigation is needed once
/// a sign-in flow completes.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Object? _oauthError;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        auth.currentSession,
      ),
      builder: (context, snapshot) {
        // getSessionFromUrl (the PKCE exchange run after the Google
        // redirect) reports failures via GoTrueClient.notifyException,
        // which lands here as a stream error rather than a thrown
        // exception anyone can try/catch. Surface it instead of quietly
        // falling back to LoginScreen with no explanation.
        if (snapshot.hasError) {
          _oauthError = snapshot.error;
        }
        final session = snapshot.data?.session ?? auth.currentSession;
        if (session != null) {
          _oauthError = null;
          return const DashboardScreen();
        }
        if (_oauthError != null) {
          return _OAuthErrorScreen(
            error: _oauthError!,
            onDismiss: () => setState(() => _oauthError = null),
          );
        }
        return const LoginScreen();
      },
    );
  }
}

/// Temporary diagnostic screen: shows the raw error from a failed Google
/// OAuth callback so it can be read directly off the device when logcat
/// isn't available (e.g. MIUI hides stdout for non-debuggable release
/// builds). Remove once the release OAuth flow is confirmed stable.
class _OAuthErrorScreen extends StatelessWidget {
  const _OAuthErrorScreen({required this.error, required this.onDismiss});

  final Object error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Error en el login con Google',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SelectableText(
                error.toString(),
                style: const TextStyle(color: Colors.redAccent, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onDismiss,
                child: const Text('Volver a intentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
