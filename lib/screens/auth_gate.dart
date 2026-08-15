import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dashboard_screen.dart';
import 'login_screen.dart';

/// Root routing widget: shows [DashboardScreen] while a Supabase session is
/// active, [LoginScreen] otherwise. Rebuilds instantly on every auth change
/// (OTP verification, Google OAuth callback, sign-out) via
/// [GoTrueClient.onAuthStateChange], so no manual navigation is needed once
/// a sign-in flow completes.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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
        final session = snapshot.data?.session ?? auth.currentSession;
        return session != null ? const DashboardScreen() : const LoginScreen();
      },
    );
  }
}
