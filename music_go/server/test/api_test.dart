import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_go_core/music_go_core.dart';
import 'package:music_go_server/music_go_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  const config = SpawnConfig();
  final now = DateTime.utc(2026, 9, 23, 12);
  final spawns = SpawnGenerator(config).spawnsNear(const GeoPoint(52.52, 13.405), 600, now);
  const player = 'test-player-1';

  // Fake Deezer: every chart returns the same two tracks.
  final fakeDeezer = MockClient((req) async => http.Response(
      jsonEncode({
        'data': [
          for (final id in [1, 2])
            {
              'id': id,
              'title': 'Song $id',
              'artist': {'name': 'Artist'},
              'album': {'title': 'Album', 'cover_medium': ''},
            }
        ]
      }),
      200));

  late Handler handler;
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mg');
    handler = GameApi(
      config: config,
      store: PlayerStore(File('${tmp.path}/players.json')),
      catalog: MusicCatalog(client: fakeDeezer),
      links: StreamingLinks(client: fakeDeezer),
      clock: () => now,
    ).router.call;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(int, Map<String, dynamic>)> post(Spawn s, GeoPoint at) async {
    final res = await handler(Request('POST', Uri.parse('http://x/api/catch'),
        body: jsonEncode({'playerId': player, 'spawnId': s.id, ...at.toJson()})));
    return (res.statusCode, jsonDecode(await res.readAsString()) as Map<String, dynamic>);
  }

  test('catch, then reject duplicate', () async {
    final s = spawns.first;
    final (status, body) = await post(s, s.position);
    expect(status, 200);
    expect((body['card'] as Map)['title'], startsWith('Song'));
    expect((body['card'] as Map)['rarity'], s.rarity.name);

    final (status2, body2) = await post(s, s.position);
    expect(status2, 422);
    expect(body2['error'], 'alreadyCaught');

    final res = await handler(Request('GET', Uri.parse('http://x/api/collection?playerId=$player')));
    final collection = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(collection['cards'], hasLength(1));
    expect(collection['caughtSpawnIds'], [s.id]);
  });

  test('rejects too far and teleport', () async {
    final a = spawns.first;
    final (tooFar, body) = await post(a, a.position.offsetMeters(200, 0));
    expect(tooFar, 422);
    expect(body['error'], 'tooFar');

    expect((await post(a, a.position)).$1, 200);
    // A spawn far away, "caught" at the same instant.
    final far = SpawnGenerator(config).spawnsNear(const GeoPoint(48.8566, 2.3522), 600, now).first;
    final (status, body2) = await post(far, far.position);
    expect(status, 422);
    expect(body2['error'], 'tooFast');
  });
}
