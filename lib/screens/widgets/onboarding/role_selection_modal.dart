import 'dart:ui';

import 'package:flutter/material.dart';

/// `profiles.role` values — shared between [RoleSelectionModal] and
/// `AuthGate` so both sides read/write the same two literals instead of
/// each hardcoding its own copy of the strings.
const String kRoleClient = 'client';
const String kRoleMusician = 'musician';

const _kSurface = Color(0xFF17171D);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

/// Opens [RoleSelectionModal] as a true dialog route (not a plain widget
/// swap) so its entrance can be a custom scale + fade rather than
/// whatever transition the caller's own screen swap uses. Non-dismissible:
/// there's no "cancel" state for "which world am I in", so a barrier tap
/// or back-gesture must not be able to leave [profiles.role] unset.
Future<void> showRoleSelectionDialog(
  BuildContext context, {
  required ValueChanged<String> onSelect,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    barrierLabel: 'Selecciona tu rol',
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, secondaryAnimation) {
      return RoleSelectionModal(onSelect: onSelect);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Immersive, first-login-only onboarding step: "¿Cómo quieres usar
/// Mussy?". `AuthGate` opens this (via [showRoleSelectionDialog]) whenever
/// `profiles.role` is still null. Picking a card calls [onSelect]
/// optimistically — `AuthGate` updates the UI and starts the persistence
/// write to Supabase in the same tick, rather than this modal blocking on
/// that network round trip before it can close.
class RoleSelectionModal extends StatefulWidget {
  const RoleSelectionModal({super.key, required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  State<RoleSelectionModal> createState() => _RoleSelectionModalState();
}

class _RoleSelectionModalState extends State<RoleSelectionModal> {
  String? _selected;

  Future<void> _pick(String role) async {
    if (_selected != null) return;
    setState(() => _selected = role);

    // A beat for the pressed card's amber glow to register before the
    // dialog itself fades out — instant pop would skip the feedback the
    // press animation just built up.
    await Future.delayed(const Duration(milliseconds: 180));
    widget.onSelect(role);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The glassmorphism blur: samples whatever `showRoleSelectionDialog`'s
        // dimmed barrier (and the screen underneath it) already painted,
        // so the content below reads as genuinely behind frosted glass
        // rather than just a flat dark overlay.
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: const SizedBox.expand(),
          ),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Bienvenido a Mussy',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '¿Cómo quieres usar la app?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 40),
                  _RoleOption(
                    emoji: '🌟',
                    title: 'Soy Cliente',
                    subtitle: 'Busco y contrato artistas para mis eventos',
                    selected: _selected == kRoleClient,
                    disabled: _selected != null && _selected != kRoleClient,
                    onTap: () => _pick(kRoleClient),
                  ),
                  const SizedBox(height: 16),
                  _RoleOption(
                    emoji: '🎸',
                    title: 'Soy Músico / Proveedor',
                    subtitle: 'Gestiono mi agrupación, portafolio y directorio',
                    selected: _selected == kRoleMusician,
                    disabled: _selected != null && _selected != kRoleMusician,
                    onTap: () => _pick(kRoleMusician),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Podrás confirmarlo de nuevo más adelante desde soporte.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A role card: presses inward on touch-down (`easeOutCubic`, quick) and
/// springs back past its resting size on release (`elasticOut`) — the
/// "achica al presionar, rebote elástico al soltar" tactile feel — plus a
/// bright amber glow once [selected] flips true.
class _RoleOption extends StatefulWidget {
  const _RoleOption({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  State<_RoleOption> createState() => _RoleOptionState();
}

class _RoleOptionState extends State<_RoleOption> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: 0,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _press() {
    if (widget.disabled) return;
    _controller.animateTo(1, duration: const Duration(milliseconds: 110), curve: Curves.easeOutCubic);
  }

  void _release() {
    if (widget.disabled) return;
    _controller.animateTo(0, duration: const Duration(milliseconds: 420), curve: Curves.elasticOut);
  }

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 1, end: 0.95).animate(_controller);

    return Opacity(
      opacity: widget.disabled ? 0.35 : 1,
      child: GestureDetector(
        onTapDown: (_) => _press(),
        onTapUp: (_) => _release(),
        onTapCancel: _release,
        onTap: widget.disabled ? null : widget.onTap,
        child: AnimatedBuilder(
          animation: scale,
          builder: (context, child) => Transform.scale(scale: scale.value, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.selected ? _kAccent : _kAccent.withValues(alpha: 0.25),
                width: widget.selected ? 2 : 1,
              ),
              boxShadow: widget.selected
                  ? [
                      BoxShadow(
                        color: _kAccent.withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Text(widget.emoji, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(color: _kTextSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                widget.selected
                    ? const Icon(Icons.check_circle_rounded, color: _kAccent)
                    : const Icon(Icons.chevron_right_rounded, color: _kAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
