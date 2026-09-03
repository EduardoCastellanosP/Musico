import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// One entry from a channel's public RSS feed.
class YoutubeVideo {
  const YoutubeVideo({
    required this.videoId,
    required this.title,
    required this.watchUrl,
    required this.thumbnailUrl,
    required this.publishedAt,
  });

  final String videoId;
  final String title;
  final String watchUrl;
  final String thumbnailUrl;

  /// From the feed entry's `<published>` tag — used as [VideoFeedItem]'s
  /// synthetic `createdAt` when this video is mixed into the Reels feed.
  final DateTime? publishedAt;
}

/// Reads a musician's YouTube uploads via the channel's public RSS feed
/// (`feeds/videos.xml?channel_id=...`) — no API key, no quota, so musicians
/// never have to paste individual video links.
class YoutubeRssService {
  const YoutubeRssService();

  static final RegExp _channelIdPattern = RegExp(r'^UC[\w-]{22}$');
  static final RegExp _videoIdPattern = RegExp(r'^[\w-]{11}$');

  /// Extracts the bare 11-char video id from whatever a caller hands in —
  /// already a bare id, a `/watch?v=`, `youtu.be/`, `/shorts/` or `/embed/`
  /// link — so a Short and a standard upload feed the same player through
  /// the same code path. Returns `null` when nothing recognizable is found.
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (_videoIdPattern.hasMatch(trimmed)) return trimmed;

    final looksLikeUrl =
        trimmed.contains('youtu.be') || trimmed.contains('youtube.com');
    final uri = Uri.tryParse(
      looksLikeUrl && !trimmed.startsWith('http') ? 'https://$trimmed' : trimmed,
    );
    if (uri == null) return null;

    final queryId = uri.queryParameters['v'];
    if (queryId != null && _videoIdPattern.hasMatch(queryId)) return queryId;

    final segments = uri.pathSegments;
    for (final marker in const ['shorts', 'embed', 'live']) {
      final index = segments.indexOf(marker);
      if (index != -1 && index + 1 < segments.length) {
        final candidate = segments[index + 1];
        if (_videoIdPattern.hasMatch(candidate)) return candidate;
      }
    }
    if (uri.host.contains('youtu.be') && segments.isNotEmpty) {
      final candidate = segments.first;
      if (_videoIdPattern.hasMatch(candidate)) return candidate;
    }
    return null;
  }

  /// YouTube serves handle/custom-channel pages a stripped-down response
  /// (no embedded channel JSON at all) to requests without a browser-like
  /// User-Agent — the default Dart UA gets this, silently breaking `@handle`
  /// resolution. A common desktop Chrome UA gets the full page instead.
  static const Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Tried in order against the channel page's raw HTML — YouTube embeds the
  /// real channel id in more than one place, and which one survives varies
  /// by A/B test, so no single pattern is reliable on its own.
  static final List<RegExp> _channelIdInHtmlPatterns = [
    RegExp(r'<link rel="canonical" href="https://www\.youtube\.com/channel/(UC[\w-]{22})"'),
    RegExp(r'"channelId":"(UC[\w-]{22})"'),
    RegExp(r'<meta itemprop="channelId" content="(UC[\w-]{22})"'),
    RegExp(r'"externalId":"(UC[\w-]{22})"'),
  ];

  /// Latest uploads for whatever the musician pasted as their channel: a
  /// bare channel id, a full `/channel/UC.../@handle//c/.../user/...` URL,
  /// or a bare `@handle`. Returns an empty list — never throws — when the
  /// channel can't be resolved or nothing can be found, so callers can
  /// render a "nothing to show" state without a try/catch of their own.
  Future<List<YoutubeVideo>> fetchLatestVideos(
    String channelInput, {
    int maxResults = 12,
  }) async {
    final channelId = await _resolveChannelId(channelInput);
    if (channelId == null) return const [];

    final fromFeed = await _fetchFromRssFeed(channelId, maxResults);
    if (fromFeed.isNotEmpty) return fromFeed;

    // The RSS feed 404s/500s for some channels even though they visibly
    // have uploads on youtube.com (seen on a freshly-active channel whose
    // feed YouTube apparently hadn't (re)generated yet) — when that
    // happens, scrape the channel's own Videos/Shorts pages directly
    // instead of just giving up.
    return _fetchByScraping(channelId, maxResults);
  }

  Future<List<YoutubeVideo>> _fetchFromRssFeed(
    String channelId,
    int maxResults,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://www.youtube.com/feeds/videos.xml?channel_id=$channelId',
            ),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return const [];

      final entries = XmlDocument.parse(response.body).findAllElements('entry');
      return entries
          .map(_parseEntry)
          .whereType<YoutubeVideo>()
          .take(maxResults)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static final RegExp _videoIdInHtmlPattern = RegExp(r'"videoId":"([\w-]{11})"');

  /// Ids scraped straight off a channel's public "Videos" or "Shorts" tab —
  /// only reached when the RSS feed comes back empty. Order reflects page
  /// order, not true chronology, since scraping has no publish-date field.
  Future<List<String>> _scrapeVideoIds(String channelId, String tab) async {
    try {
      final response = await http
          .get(
            Uri.parse('https://www.youtube.com/channel/$channelId/$tab'),
            headers: _browserHeaders,
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return const [];
      return _videoIdInHtmlPattern
          .allMatches(response.body)
          .map((match) => match.group(1)!)
          .toSet()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<YoutubeVideo>> _fetchByScraping(
    String channelId,
    int maxResults,
  ) async {
    final scraped = await Future.wait([
      _scrapeVideoIds(channelId, 'videos'),
      _scrapeVideoIds(channelId, 'shorts'),
    ]);
    final ids = {...scraped[0], ...scraped[1]}.take(maxResults);
    final videos = await Future.wait(ids.map(_fetchVideoViaOEmbed));
    return videos.whereType<YoutubeVideo>().toList();
  }

  /// Builds a [YoutubeVideo] purely from oEmbed metadata — the fallback
  /// path's only source of a title, since scraped ids carry no RSS `<entry>`
  /// alongside them. Skips the video (returns `null`) rather than showing
  /// it untitled when oEmbed itself fails.
  Future<YoutubeVideo?> _fetchVideoViaOEmbed(String videoId) async {
    final data = await _fetchOEmbed(videoId);
    final title = data?['title'] as String?;
    if (title == null) return null;
    return YoutubeVideo(
      videoId: videoId,
      title: title,
      watchUrl: 'https://www.youtube.com/watch?v=$videoId',
      thumbnailUrl: data?['thumbnail_url'] as String? ??
          'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
      publishedAt: null,
    );
  }

  /// Real aspect ratio (width / height) for [videoId], via YouTube's public
  /// oEmbed endpoint. [_fetchOEmbed] queries it through a `/shorts/` URL
  /// specifically — that's the only form that reflects a Short's true
  /// vertical dimensions; the same id queried via `/watch?v=` always
  /// reports 16:9, short or not. Falls back to 16:9 on any failure, so
  /// callers can size the player without a try/catch of their own.
  Future<double> fetchAspectRatio(String videoId) async {
    final data = await _fetchOEmbed(videoId);
    final width = (data?['width'] as num?)?.toDouble();
    final height = (data?['height'] as num?)?.toDouble();
    if (width == null || height == null || height == 0) return 16 / 9;
    return width / height;
  }

  Future<Map<String, dynamic>?> _fetchOEmbed(String videoId) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://www.youtube.com/oembed?url=https://www.youtube.com/shorts/$videoId&format=json',
            ),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  YoutubeVideo? _parseEntry(XmlElement entry) {
    final videoId = _text(entry, 'yt:videoId');
    final title = _text(entry, 'title');
    if (videoId == null || videoId.isEmpty || title == null) return null;
    return YoutubeVideo(
      videoId: videoId,
      title: title,
      watchUrl: 'https://www.youtube.com/watch?v=$videoId',
      thumbnailUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
      publishedAt: DateTime.tryParse(_text(entry, 'published') ?? ''),
    );
  }

  String? _text(XmlElement parent, String tag) {
    final elements = parent.findElements(tag);
    return elements.isEmpty ? null : elements.first.innerText.trim();
  }

  /// A bare channel id needs no lookup. A `/channel/UC.../` URL or a
  /// `channel_id=` query param already carries it too. Anything else
  /// (`@handle`, `/c/name`, `/user/name`) only resolves via the channel
  /// page's HTML, which YouTube always embeds as `"channelId":"UC..."`.
  Future<String?> _resolveChannelId(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (_channelIdPattern.hasMatch(trimmed)) return trimmed;

    final looksLikeUrl = trimmed.startsWith('http') || trimmed.contains('youtube.com');
    final uri = Uri.tryParse(
      looksLikeUrl
          ? (trimmed.startsWith('http') ? trimmed : 'https://$trimmed')
          : 'https://www.youtube.com/${trimmed.startsWith('@') ? trimmed : '@$trimmed'}',
    );
    if (uri == null) return null;

    final segments = uri.pathSegments;
    final channelIndex = segments.indexOf('channel');
    if (channelIndex != -1 && channelIndex + 1 < segments.length) {
      final candidate = segments[channelIndex + 1];
      if (_channelIdPattern.hasMatch(candidate)) return candidate;
    }
    final queryId = uri.queryParameters['channel_id'];
    if (queryId != null && _channelIdPattern.hasMatch(queryId)) return queryId;

    try {
      final response = await http
          .get(uri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      for (final pattern in _channelIdInHtmlPatterns) {
        final match = pattern.firstMatch(response.body);
        if (match != null) return match.group(1);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
