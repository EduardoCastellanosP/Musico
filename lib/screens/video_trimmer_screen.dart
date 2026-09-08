import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';

import '../core/constants/media_limits.dart';
import '../core/theme/app_theme.dart';

/// Local video trim step before upload: lets the musician pick up to
/// [MediaLimits.maxVideoDuration] out of a longer clip instead of the app
/// rejecting it outright. Pop with the trimmed [File] on success, or `null`
/// if the user backs out — the caller (`StatusScreen._addVideo`) feeds that
/// file into the existing compress/upload pipeline exactly like a
/// short-enough clip picked directly from the gallery.
class VideoTrimmerScreen extends StatefulWidget {
  const VideoTrimmerScreen({super.key, required this.videoFile});

  final File videoFile;

  @override
  State<VideoTrimmerScreen> createState() => _VideoTrimmerScreenState();
}

class _VideoTrimmerScreenState extends State<VideoTrimmerScreen> {
  final Trimmer _trimmer = Trimmer();

  bool _isTrimmerReady = false;
  bool _isPlaying = false;
  bool _isSaving = false;
  double _startValue = 0;
  double _endValue = 0;

  @override
  void initState() {
    super.initState();
    _trimmer.eventStream.listen((event) {
      if (event == TrimmerEvent.initialized && mounted) {
        setState(() => _isTrimmerReady = true);
      }
    });
    _trimmer.loadVideo(videoFile: widget.videoFile);
  }

  @override
  void dispose() {
    // `VideoViewer` calls `_trimmer.dispose()` on unmount, but that only
    // closes the event stream — the underlying video_player controller is
    // never released by the package itself, so it's disposed here.
    _trimmer.videoPlayerController?.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final playing = await _trimmer.videoPlaybackControl(
      startValue: _startValue,
      endValue: _endValue,
    );
    if (!mounted) return;
    setState(() => _isPlaying = playing);
  }

  Future<void> _saveTrimmedVideo() async {
    if (_isSaving || !_isTrimmerReady) return;
    if (_endValue - _startValue < 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos 1 segundo de video.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    String? outputPath;
    try {
      await _trimmer.saveTrimmedVideo(
        startValue: _startValue,
        endValue: _endValue,
        onSave: (path) => outputPath = path,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos recortar el video: $error')),
      );
      return;
    }

    if (!mounted) return;
    if (outputPath == null) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos recortar el video.')),
      );
      return;
    }
    Navigator.of(context).pop(File(outputPath!));
  }

  String _formatDuration(double milliseconds) {
    final duration = Duration(milliseconds: milliseconds.toInt());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final maxLength = MediaLimits.maxVideoDuration;
    final selectedLabel =
        '${_formatDuration(_endValue - _startValue)} / ${_formatDuration(maxLength.inMilliseconds.toDouble())}';

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: Colors.white,
        title: const Text('Recortar video'),
      ),
      body: SafeArea(
        child: !_isTrimmerReady
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.profileAccent),
              )
            : Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: GestureDetector(
                          onTap: _togglePlayback,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoViewer(trimmer: _trimmer),
                              if (!_isPlaying)
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Selección: $selectedLabel',
                          style: const TextStyle(
                            color: AppColors.darkTextSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          onPressed: _togglePlayback,
                          icon: Icon(
                            _isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                            color: AppColors.profileAccent,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: TrimViewer(
                      trimmer: _trimmer,
                      viewerHeight: 60,
                      viewerWidth: MediaQuery.of(context).size.width - 24,
                      maxVideoLength: maxLength,
                      durationStyle: DurationStyle.FORMAT_MM_SS,
                      durationTextStyle: const TextStyle(color: Colors.white, fontSize: 12),
                      editorProperties: const TrimEditorProperties(
                        circlePaintColor: AppColors.profileAccent,
                        borderPaintColor: AppColors.profileAccent,
                        scrubberPaintColor: AppColors.profileAccent,
                        borderWidth: 3,
                        circleSize: 6,
                      ),
                      areaProperties: const TrimAreaProperties(borderRadius: 12),
                      onChangeStart: (value) => _startValue = value,
                      onChangeEnd: (value) => _endValue = value,
                      onChangePlaybackState: (playing) {
                        if (mounted) setState(() => _isPlaying = playing);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _saveTrimmedVideo,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.profileAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.content_cut_rounded),
                        label: Text(
                          _isSaving ? 'Procesando...' : 'Recortar y Guardar',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
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
