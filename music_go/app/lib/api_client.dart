import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:music_go_core/music_go_core.dart';

/// Where the game server lives. On the web the app is served by the server
/// itself, so the page origin is right; override with
/// `--dart-define=API_BASE=http://host:port` (e.g. for `flutter run`).
String resolveApiBase() {
  const override = String.fromEnvironment('API_BASE');
  if (override.isNotEmpty) return override;
  if (kIsWeb) return Uri.base.origin;
  return 'http://10.0.2.2:8080'; // Android emulator -> host machine.
}

class CatchFailed implements Exception {
  CatchFailed(this.reason, this.distanceMeters);

  /// A [CatchRejection] name, or `network`.
  final String reason;
  final double? distanceMeters;
}

class CatchResult {
  CatchResult(this.card, this.isNew);

  final TrackCard card;
  final bool isNew;
}

class TrackDetails {
  TrackDetails({this.previewUrl, this.coverUrl});

  final String? previewUrl;
  final String? coverUrl;
}

class ApiClient {
  ApiClient(this.baseUrl);

  final String baseUrl;
  final _http = http.Client();

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final res = await _http.get(uri).timeout(const Duration(seconds: 15));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<SpawnConfig> config() async =>
      SpawnConfig.fromJson((await _getJson(_u('/api/config')))['spawn'] as Map<String, dynamic>);

  Future<CatchResult> catchSpawn(String playerId, String spawnId, GeoPoint at) async {
    final http.Response res;
    try {
      res = await _http
          .post(_u('/api/catch'),
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'playerId': playerId, 'spawnId': spawnId, ...at.toJson()}))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw CatchFailed('network', null);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw CatchFailed(body['error'] as String? ?? 'network',
          (body['distanceMeters'] as num?)?.toDouble());
    }
    return CatchResult(
        TrackCard.fromJson(body['card'] as Map<String, dynamic>), body['isNew'] as bool);
  }

  Future<(List<TrackCard>, Set<String>)> collection(String playerId) async {
    final j = await _getJson(_u('/api/collection', {'playerId': playerId}));
    final cards = (j['cards'] as List).cast<Map<String, dynamic>>().map(TrackCard.fromJson).toList();
    return (cards, (j['caughtSpawnIds'] as List).cast<String>().toSet());
  }

  Future<TrackDetails> track(String trackId) async {
    final j = await _getJson(_u('/api/track', {'trackId': trackId}));
    return TrackDetails(previewUrl: j['previewUrl'] as String?, coverUrl: j['coverUrl'] as String?);
  }

  Future<Map<String, String>> links(TrackCard card) async {
    final j = await _getJson(_u('/api/links',
        {'trackId': card.trackId, 'title': card.title, 'artist': card.artist}));
    return j.map((k, v) => MapEntry(k, v as String));
  }
}
