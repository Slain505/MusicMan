import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:music_go_core/music_go_core.dart';

/// Stable metadata of a track. Previews are fetched separately because
/// Deezer's preview URLs are signed and expire.
class CatalogTrack {
  const CatalogTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String coverUrl;

  factory CatalogTrack.fromDeezer(Map<String, dynamic> t) => CatalogTrack(
        id: 'deezer:${t['id']}',
        title: t['title'] as String,
        artist: (t['artist'] as Map)['name'] as String,
        album: (t['album'] as Map?)?['title'] as String? ?? '',
        coverUrl: (t['album'] as Map?)?['cover_medium'] as String? ?? '',
      );
}

/// Picks tracks for spawns from Deezer genre charts (free, no API key).
/// Falls back to a tiny offline pool so the game works without internet.
class MusicCatalog {
  MusicCatalog({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final Map<Genre, _CachedPool> _pools = {};
  final Map<String, Map<String, dynamic>> _details = {};

  static const _cacheTtl = Duration(hours: 6);

  static const Map<Genre, int> deezerGenreIds = {
    Genre.pop: 132,
    Genre.hiphop: 116,
    Genre.rock: 152,
    Genre.electronic: 106,
    Genre.rnb: 165,
    Genre.alternative: 85,
    Genre.jazz: 129,
    Genre.classical: 98,
  };

  /// Deterministic: the same spawn yields the same track while the chart
  /// doesn't change.
  Future<CatalogTrack> trackFor(Spawn spawn) async {
    final pool = await _pool(spawn.genre);
    return pool[spawn.trackSeed % pool.length];
  }

  Future<List<CatalogTrack>> _pool(Genre genre) async {
    final cached = _pools[genre];
    if (cached != null && DateTime.now().difference(cached.at) < _cacheTtl) {
      return cached.tracks;
    }
    var tracks = await _chart(deezerGenreIds[genre]!);
    // Some genre charts are empty in some regions; the global chart isn't.
    if (tracks.isEmpty) tracks = await _chart(0);
    if (tracks.isEmpty) return cached?.tracks ?? _offlinePool;
    _pools[genre] = _CachedPool(tracks, DateTime.now());
    return tracks;
  }

  Future<List<CatalogTrack>> _chart(int deezerGenreId) async {
    try {
      final res = await _http
          .get(Uri.parse('https://api.deezer.com/chart/$deezerGenreId/tracks?limit=100'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final data = (jsonDecode(res.body) as Map<String, dynamic>)['data'] as List? ?? [];
      return data.cast<Map<String, dynamic>>().map(CatalogTrack.fromDeezer).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fresh preview URL and large cover for a track id like `deezer:3135556`.
  Future<Map<String, dynamic>> details(String trackId) async {
    final cached = _details[trackId];
    // Preview URLs are signed for a limited time; refetch after ~10 minutes.
    if (cached != null &&
        DateTime.now().difference(cached['_at'] as DateTime) < const Duration(minutes: 10)) {
      return Map.of(cached)..remove('_at');
    }
    if (!trackId.startsWith('deezer:')) return {'previewUrl': null};
    try {
      final id = trackId.substring('deezer:'.length);
      final res = await _http
          .get(Uri.parse('https://api.deezer.com/track/$id'))
          .timeout(const Duration(seconds: 8));
      final t = jsonDecode(res.body) as Map<String, dynamic>;
      final result = <String, dynamic>{
        'previewUrl': (t['preview'] as String?)?.isNotEmpty == true ? t['preview'] : null,
        'coverUrl': (t['album'] as Map?)?['cover_big'],
        'deezerUrl': t['link'],
      };
      _details[trackId] = {...result, '_at': DateTime.now()};
      return result;
    } catch (_) {
      return {'previewUrl': null};
    }
  }

  static const _offlinePool = [
    CatalogTrack(id: 'offline:1', title: 'Offline Groove', artist: 'Music GO', album: 'No Signal', coverUrl: ''),
    CatalogTrack(id: 'offline:2', title: 'Street Echo', artist: 'Music GO', album: 'No Signal', coverUrl: ''),
    CatalogTrack(id: 'offline:3', title: 'Walking Bass', artist: 'Music GO', album: 'No Signal', coverUrl: ''),
  ];
}

class _CachedPool {
  _CachedPool(this.tracks, this.at);

  final List<CatalogTrack> tracks;
  final DateTime at;
}
