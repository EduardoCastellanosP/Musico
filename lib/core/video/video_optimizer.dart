import 'dart:io';

import 'package:video_compress/video_compress.dart';

/// Upload-time video pipeline every clip must go through before it reaches
/// Supabase Storage (`musician-videos` bucket). Every byte stored here
/// counts against the project's Storage *and* Egress quota again on every
/// single playback in [VideoFeedScreen], so keeping the source small isn't
/// just faster uploads — it's the main cost lever the app has.
abstract final class VideoOptimizer {
  /// Re-encodes [sourcePath] to 720p (`video_compress` only exposes named
  /// presets, not a raw bitrate knob — `Res1280x720Quality` is its 720p
  /// preset, already a large cut from a raw phone-camera recording).
  /// Throws [StateError] if compression fails; callers should treat that as
  /// fatal rather than fall back to uploading the uncompressed source.
  static Future<File> compressForUpload(String sourcePath) async {
    final info = await VideoCompress.compressVideo(
      sourcePath,
      quality: VideoQuality.Res1280x720Quality,
      deleteOrigin: false,
      frameRate: 30,
    );
    final file = info?.file;
    if (file == null) {
      throw StateError('No pudimos comprimir el video.');
    }
    return file;
  }

  /// A single JPEG frame from [sourcePath] — the "thumbnail first" half of
  /// the feed's lazy-load strategy: [VideoFeedScreen] can show this
  /// near-instantly while the real video (orders of magnitude heavier)
  /// only starts downloading once that page actually becomes current.
  static Future<File> generateThumbnail(String sourcePath) {
    return VideoCompress.getFileThumbnail(sourcePath, quality: 60);
  }
}
