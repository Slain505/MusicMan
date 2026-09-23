import 'dart:convert';

import 'package:http/http.dart' as http;

/// Links to the same track on other services via Odesli (song.link).
///
/// Odesli's free tier allows ~10 requests/minute, so results are cached
/// forever and we fall back to plain search links when it's unavailable.
class StreamingLinks {
  StreamingLinks({http.Client? client, this.apiKey})
      : _http = client ?? http.Client();

  final http.Client _http;

  /// Odesli now answers 401 without a key; request one from them and pass it
  /// via the ODESLI_API_KEY environment variable.
  final String? apiKey;
  final Map<String, Map<String, String>> _cache = {};

  static const _platforms = {
    'spotify': 'spotify',
    'appleMusic': 'appleMusic',
    'youtube': 'youtube',
    'youtubeMusic': 'youtubeMusic',
    'deezer': 'deezer',
  };

  Future<Map<String, String>> linksFor({
    required String trackId,
    required String title,
    required String artist,
  }) async {
    final cached = _cache[trackId];
    if (cached != null) return cached;

    final found = <String, String>{};
    if (trackId.startsWith('deezer:')) {
      final deezerUrl = 'https://www.deezer.com/track/${trackId.substring(7)}';
      if (apiKey == null) {
        found['deezer'] = deezerUrl;
        return {..._searchLinks('$artist $title'), ...found};
      }
      try {
        final res = await _http
            .get(Uri.https('api.song.link', '/v1-alpha.1/links', {'url': deezerUrl, 'key': apiKey!}))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final byPlatform = (jsonDecode(res.body) as Map<String, dynamic>)['linksByPlatform']
                  as Map<String, dynamic>? ??
              {};
          _platforms.forEach((key, platform) {
            final url = (byPlatform[platform] as Map?)?['url'] as String?;
            if (url != null) found[key] = url;
          });
        }
      } catch (_) {
        // Fall through to search links.
      }
      found.putIfAbsent('deezer', () => deezerUrl);
    }

    final complete = found.containsKey('spotify') && found.containsKey('youtube');
    final result = {..._searchLinks('$artist $title'), ...found};
    // Only cache real Odesli answers; retry search-only results later.
    if (complete) _cache[trackId] = result;
    return result;
  }

  Map<String, String> _searchLinks(String query) {
    final q = Uri.encodeComponent(query);
    return {
      'spotify': 'https://open.spotify.com/search/$q',
      'appleMusic': 'https://music.apple.com/search?term=$q',
      'youtube': 'https://www.youtube.com/results?search_query=$q',
    };
  }
}
