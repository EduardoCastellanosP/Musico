import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const _kBackground = Color(0xFF0D0D12);
const _kAccent = Color(0xFFFFB703);
const _kTextSecondary = Color(0xFF9A9AA5);

/// What [BlockingProgressDialog] shows at any given moment — a single
/// object (rather than separate title/subtitle/progress listenables) so
/// a caller updating several fields at once (e.g. moving to the next
/// upload step) only ever triggers one rebuild, not three.
@immutable
class BlockingProgressState {
  const BlockingProgressState({required this.title, this.subtitle, this.percent});

  /// e.g. "Comprimiendo video...".
  final String title;

  /// e.g. "Esto puede tardar un momento." Shown as-is while [percent] is
  /// null; prefixed with the percentage once it isn't.
  final String? subtitle;

  /// `null` for an indeterminate spinner (no real progress source — true
  /// for most uploads); 0-100 for a determinate ring when the caller has
  /// a genuine percentage (e.g. `VideoCompress.compressProgress$`).
  final double? percent;
}

/// Blocking "processing" modal for any upload/compression step long
/// enough to feel broken as a plain SnackBar — dark/gold, centered,
/// undismissable (`PopScope(canPop: false)` + the caller's
/// `barrierDismissible: false`) so the user can't walk away mid-operation.
/// Reused across every long-running upload in the app instead of each
/// screen hand-rolling its own version of the same modal.
class BlockingProgressDialog extends StatelessWidget {
  const BlockingProgressDialog({super.key, required this.state});

  final ValueListenable<BlockingProgressState> state;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: _kBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
          ),
          child: ValueListenableBuilder<BlockingProgressState>(
            valueListenable: state,
            builder: (context, value, _) {
              final percent = value.percent?.clamp(0, 100);
              final subtitle = value.subtitle;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      color: _kAccent,
                      value: percent == null ? null : percent / 100,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    value.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      percent == null ? subtitle : '${percent.toStringAsFixed(0)}% — $subtitle',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _kTextSecondary, fontSize: 13),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Opens [BlockingProgressDialog] and returns a closer to call once the
/// operation finishes (success or failure) — update [state]`.value` as
/// the operation progresses through its steps, then invoke the closer.
///
/// Caller contract, same footgun every ad hoc `showDialog`+manual-pop
/// used to hit individually: only call this (and only invoke the
/// returned closer) while `context.mounted` is true. Neither this
/// function nor the closer re-checks that for you.
VoidCallback showBlockingProgressDialog(
  BuildContext context, {
  required ValueListenable<BlockingProgressState> state,
}) {
  var shown = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlockingProgressDialog(state: state),
  );
  return () {
    if (!shown) return;
    shown = false;
    Navigator.of(context, rootNavigator: true).pop();
  };
}
