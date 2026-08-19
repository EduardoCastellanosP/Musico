import 'package:flutter/material.dart';

/// Dashboard header's quick availability toggle — solid green when
/// [isFree], solid red otherwise, next to a matching "Estado: ..." label.
/// Purely presentational: [DashboardScreen] owns the optimistic-update
/// logic and hands this widget a plain `bool`/callback pair.
class AvailabilitySwitch extends StatelessWidget {
  const AvailabilitySwitch({
    super.key,
    required this.isFree,
    required this.onChanged,
  });

  final bool isFree;
  final ValueChanged<bool> onChanged;

  static const Color _freeColor = Color(0xFF22C55E);
  static const Color _busyColor = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = isFree ? _freeColor : _busyColor;

    return Row(
      children: [
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
              children: [
                const TextSpan(text: 'Estado: '),
                TextSpan(
                  text: isFree ? 'Disponible' : 'Ocupado',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        Switch.adaptive(
          value: isFree,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: _freeColor,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: _busyColor,
        ),
      ],
    );
  }
}
