import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/musician_repository.dart';
import 'admin_dashboard_screen.dart';
import 'client_home_screen.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'widgets/onboarding/role_selection_modal.dart';

/// Root routing widget: shows [LoginScreen] with no active Supabase
/// session; once one exists, [AdminDashboardScreen] for any
/// `profiles.is_admin` account, otherwise [HomeShell] (`role ==
/// 'musician'`) or [ClientHomeScreen] (`role == 'client'`) — see
/// [MusicianRepository.currentProfileIsAdmin]/`currentProfileRole` and
/// `supabase/schema.sql` §21. On first login (`profiles.role` still null)
/// it pops open [RoleSelectionModal] as its own dialog route via
/// [showRoleSelectionDialog] rather than swapping it in as a plain
/// destination — that's what lets it use a custom scale/fade entrance
/// instead of whatever transition [_fluidSwitcher] uses for everything
/// else. Rebuilds instantly on every auth change (OTP verification, Google
/// OAuth callback, sign-out) via [GoTrueClient.onAuthStateChange], so no
/// manual navigation is needed once a sign-in flow completes.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _musicianRepository = MusicianRepository();

  Object? _oauthError;

  // Memoized per signed-in user id — `onAuthStateChange` also fires on
  // token refresh, not just login, so without this the role check would
  // re-run (and flash the loading spinner) on every silent token refresh.
  String? _adminCheckUserId;
  Future<bool>? _isAdminFuture;

  // Set inside the `catchError` below when the role check fails over the
  // network — kept separately from `_isAdminFuture` because that future
  // always resolves to a plain `false` (fail open to the client flow), so
  // `FutureBuilder` alone can't tell "not admin" apart from "couldn't check".
  Object? _adminCheckError;

  // Guards the "couldn't verify role" SnackBar so a rebuild (e.g. the
  // token-refresh events `onAuthStateChange` also emits) doesn't queue it
  // again for the same failed check.
  bool _roleCheckErrorShown = false;

  Future<bool> _isAdminFor(String userId) {
    if (_adminCheckUserId != userId) {
      _adminCheckUserId = userId;
      _roleCheckErrorShown = false;
      _adminCheckError = null;
      // Falls back to "not admin" on network failure — a musician's whole
      // login shouldn't hang or fail just because the role check couldn't
      // reach Supabase — [_adminCheckError] is what lets the builder below
      // still warn the user their role may be stale.
      _isAdminFuture = _musicianRepository
          .currentProfileIsAdmin()
          .catchError((error) {
            debugPrint('No se pudo verificar el rol de administrador: $error');
            _adminCheckError = error;
            return false;
          });
    }
    return _isAdminFuture!;
  }

  void _warnRoleCheckFailedOnceAfterBuild() {
    if (_roleCheckErrorShown) return;
    _roleCheckErrorShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos verificar tu rol por un problema de red. '
            'Entrando como cliente.',
          ),
        ),
      );
    });
  }

  // Same memoization idea as `_isAdminFor`, for `profiles.role`.
  String? _worldCheckUserId;
  Future<String?>? _worldFuture;

  // Set by `_handleRoleSelected` the instant a card is tapped — optimistic,
  // ahead of the Supabase write actually confirming — so the very next
  // build routes to the chosen screen immediately. Without this, the
  // already-memoized `_worldFuture` would keep resolving to the stale
  // `null` it cached before the user ever picked a role.
  String? _roleOverride;

  // Guards against opening `showRoleSelectionDialog` more than once for
  // the same null-role session — `StreamBuilder`/`FutureBuilder` can
  // rebuild several times (token refresh, etc.) while the dialog is
  // already showing.
  bool _roleDialogOpen = false;

  Future<String?> _worldFor(String userId) {
    if (_worldCheckUserId != userId) {
      _worldCheckUserId = userId;
      _roleOverride = null;
      _roleDialogOpen = false;
      _worldFuture = _musicianRepository.currentProfileRole();
    }
    return _worldFuture!;
  }

  void _maybeShowRoleDialog() {
    if (_roleDialogOpen) return;
    _roleDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showRoleSelectionDialog(context, onSelect: _handleRoleSelected);
    });
  }

  /// Optimistic: flips the UI to the chosen destination in this same
  /// frame, then fires the Supabase write in the background rather than
  /// making the smooth post-dialog transition wait on a round trip. A
  /// failed write just gets a `SnackBar` — `profiles.role` stays null
  /// server-side, so the dialog simply asks again next login, which is an
  /// acceptable fallback for something this low-stakes.
  void _handleRoleSelected(String role) {
    setState(() {
      _roleOverride = role;
      _roleDialogOpen = false;
    });
    _musicianRepository.updateCurrentProfileRole(role).catchError((error) {
      debugPrint('No se pudo guardar el rol elegido: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo guardar tu elección ($error). Te preguntaremos de nuevo en tu próximo ingreso.',
          ),
        ),
      );
    });
  }

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

        Widget child;
        Key key;
        if (session != null) {
          _oauthError = null;
          child = FutureBuilder<bool>(
            future: _isAdminFor(session.user.id),
            builder: (context, adminSnapshot) {
              // Loading (or a failed role check, which fails safe to the
              // normal client flow rather than blocking access entirely) —
              // a plain spinner avoids flashing HomeShell/AdminDashboard
              // and then swapping it out a moment later.
              if (adminSnapshot.connectionState != ConnectionState.done) {
                return const _RoleCheckLoading();
              }
              if (_adminCheckError != null) {
                _warnRoleCheckFailedOnceAfterBuild();
              }

              if (adminSnapshot.data == true) {
                return _fluidSwitcher(
                  child: const KeyedSubtree(
                    key: ValueKey('admin'),
                    child: AdminDashboardScreen(),
                  ),
                );
              }

              return FutureBuilder<String?>(
                future: _worldFor(session.user.id),
                builder: (context, roleSnapshot) {
                  if (roleSnapshot.connectionState != ConnectionState.done) {
                    return const _RoleCheckLoading();
                  }

                  final role = _roleOverride ?? roleSnapshot.data;

                  Widget destination;
                  Key destinationKey;
                  if (role == kRoleMusician) {
                    destination = const HomeShell();
                    destinationKey = const ValueKey('musician-home');
                  } else if (role == kRoleClient) {
                    destination = const ClientHomeScreen();
                    destinationKey = const ValueKey('client-home');
                  } else {
                    // First login: `profiles.role` is still null. The
                    // dialog itself is opened as a real route (see
                    // `_maybeShowRoleDialog`) so it gets its own scale/fade
                    // entrance — this backdrop is just what shows (blurred,
                    // via the dialog's own BackdropFilter) underneath it.
                    _maybeShowRoleDialog();
                    destination = const _RoleCheckLoading();
                    destinationKey = const ValueKey('role-selection-backdrop');
                  }
                  return _fluidSwitcher(
                    child: KeyedSubtree(key: destinationKey, child: destination),
                  );
                },
              );
            },
          );
          key = const ValueKey('authed');
        } else if (_oauthError != null) {
          child = _OAuthErrorScreen(
            error: _oauthError!,
            onDismiss: () => setState(() => _oauthError = null),
          );
          key = const ValueKey('oauth-error');
        } else {
          child = const LoginScreen();
          key = const ValueKey('login');
        }

        return _fluidSwitcher(child: KeyedSubtree(key: key, child: child));
      },
    );
  }
}

/// Fade + a subtle lateral slide-in, instead of `AnimatedSwitcher`'s bare
/// default fade — the "transiciones sin fricción" feel used for every
/// screen swap this widget makes (login ↔ authed, admin/role-check
/// loading ↔ final destination).
Widget _fluidSwitcher({required Widget child}) {
  return AnimatedSwitcher(
    duration: const Duration(milliseconds: 350),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.02, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: child,
  );
}

class _RoleCheckLoading extends StatelessWidget {
  const _RoleCheckLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D0D12),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFFFFB703)),
      ),
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
