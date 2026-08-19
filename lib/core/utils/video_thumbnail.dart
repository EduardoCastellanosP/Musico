/// Derives a free YouTube thumbnail URL (no API key, no extra dependency)
/// from a watch/shorts/short-link URL; returns `null` for anything else —
/// notably Vimeo, which needs an oEmbed round-trip to get a real thumbnail,
/// not worth it for an MVP. Callers fall back to a generic placeholder tile
/// when this returns `null`.
String? youtubeThumbnail(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();

  String? videoId;
  if (host.contains('youtu.be')) {
    videoId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  } else if (host.contains('youtube.com')) {
    videoId = uri.queryParameters['v'];
    if (videoId == null && uri.pathSegments.contains('shorts')) {
      final index = uri.pathSegments.indexOf('shorts');
      if (index + 1 < uri.pathSegments.length) {
        videoId = uri.pathSegments[index + 1];
      }
    }
  }
  if (videoId == null || videoId.isEmpty) return null;
  return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
}
