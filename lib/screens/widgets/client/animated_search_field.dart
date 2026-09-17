import 'dart:async';

import 'package:flutter/material.dart';

const _kInputSurface = Color(0xFF1A1A24);
const _kTextSecondary = Color(0xFF9A9AA5);

const _kSuggestions = [
  'Músicos',
  'DJs',
  'Discotecas',
  'Agrupaciones vallenatas',
  'Reggaetón',
  'Mariachis',
  'Catering',
  'Fotografía',
];

const _kTypeSpeed = Duration(milliseconds: 100);
const _kDeleteSpeed = Duration(milliseconds: 50);
const _kWordPause = Duration(milliseconds: 1800);
const _kNextWordPause = Duration(milliseconds: 300);

/// Tarima's search bar with a native "typewriter" hint — cycles through
/// [_kSuggestions], typing/pausing/deleting on a plain `Timer` (no
/// `animated_text_kit` or similar: a rescheduled `Timer` writing a `String`
/// into state is all this needs). Pauses itself the moment the field gains
/// focus or has real text in it, so the illusion never fights the user's
/// own typing.
class AnimatedSearchField extends StatefulWidget {
  const AnimatedSearchField({super.key, this.onChanged, this.onSubmitted});

  /// Fires with the field's real text — the animated hint never touches
  /// this, it only ever changes `InputDecoration.hintText`.
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AnimatedSearchField> createState() => _AnimatedSearchFieldState();
}

class _AnimatedSearchFieldState extends State<AnimatedSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _timer;

  int _wordIndex = 0;
  int _charCount = 0;
  bool _deleting = false;
  String _hint = '';

  // True whenever the field has focus or real text — the animation stops
  // dead and the hint is hidden entirely while this holds.
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_syncPauseState);
    _controller.addListener(_syncPauseState);
    _tick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.removeListener(_syncPauseState);
    _controller.removeListener(_syncPauseState);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncPauseState() {
    final shouldPause = _focusNode.hasFocus || _controller.text.isNotEmpty;
    if (shouldPause == _paused) return;
    setState(() => _paused = shouldPause);
    if (shouldPause) {
      _timer?.cancel();
    } else {
      // Resumes exactly where the current word left off — mid-type or
      // mid-delete — rather than restarting it from scratch.
      _tick();
    }
  }

  void _tick() {
    if (!mounted || _paused) return;

    final word = _kSuggestions[_wordIndex];

    if (!_deleting) {
      if (_charCount < word.length) {
        _charCount++;
        setState(() => _hint = word.substring(0, _charCount));
        _timer = Timer(_kTypeSpeed, _tick);
      } else {
        _timer = Timer(_kWordPause, () {
          _deleting = true;
          _tick();
        });
      }
      return;
    }

    if (_charCount > 0) {
      _charCount--;
      setState(() => _hint = word.substring(0, _charCount));
      _timer = Timer(_kDeleteSpeed, _tick);
    } else {
      _deleting = false;
      _wordIndex = (_wordIndex + 1) % _kSuggestions.length;
      _timer = Timer(_kNextWordPause, _tick);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _kInputSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search, color: _kTextSecondary),
            // Hidden the instant the field is focused or has real text —
            // never fights the user's own typing for the same space.
            hintText: _paused ? '' : _hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}
