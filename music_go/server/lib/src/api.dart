import 'dart:convert';

import 'package:music_go_core/music_go_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'music_catalog.dart';
import 'player_store.dart';
import 'streaming_links.dart';

final _playerIdPattern = RegExp(r'^[A-Za-z0-9-]{8,64}$');

class GameApi {
  GameApi({
    required this.config,
    required this.store,
    required this.catalog,
    required this.links,
    DateTime Function()? clock,
  })  : _validator = CatchValidator(SpawnGenerator(config)),
        _now = clock ?? (() => DateTime.now().toUtc());

  final SpawnConfig config;
  final PlayerStore store;
  final MusicCatalog catalog;
  final StreamingLinks links;
  final CatchValidator _validator;
  final DateTime Function() _now;

  Router get router => Router()
    ..get('/api/config', _config)
    ..post('/api/catch', _catch)
    ..get('/api/collection', _collection)
    ..get('/api/track', _track)
    ..get('/api/links', _links);

  Response _config(Request _) => _json({'spawn': config.toJson(), 'serverTime': _now().toIso8601String()});

  Future<Response> _catch(Request req) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _json({'error': 'badRequest'}, 400);
    }
    final playerId = body['playerId'];
    final spawnId = body['spawnId'];
    if (playerId is! String || !_playerIdPattern.hasMatch(playerId) || spawnId is! String) {
      return _json({'error': 'badRequest'}, 400);
    }
    final position = GeoPoint.fromJson(body);
    final now = _now();
    final player = store.get(playerId);
    store.pruneExpired(player, now);

    final check = _validator.check(
      spawnId: spawnId,
      position: position,
      now: now,
      lastTrace: player.lastTrace,
      alreadyCaught: player.caughtSpawns.containsKey(spawnId),
    );
    if (!check.ok) {
      return _json({'error': check.rejection!.name, 'distanceMeters': check.distanceMeters}, 422);
    }

    final spawn = check.spawn!;
    final track = await catalog.trackFor(spawn);
    final fresh = TrackCard(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      coverUrl: track.coverUrl,
      genre: spawn.genre,
      rarity: spawn.rarity,
      spawnId: spawn.id,
      caughtAt: now,
    );
    final existing = player.cards[fresh.collectionKey];
    final card = existing == null ? fresh : existing.copyWith(count: existing.count + 1, caughtAt: now);

    player.cards[card.collectionKey] = card;
    player.caughtSpawns[spawn.id] = spawn.expiresAt;
    player.lastTrace = PlayerTrace(position, now);
    store.scheduleSave();

    return _json({'card': card.toJson(), 'isNew': existing == null});
  }

  Response _collection(Request req) {
    final playerId = req.url.queryParameters['playerId'] ?? '';
    if (!_playerIdPattern.hasMatch(playerId)) return _json({'error': 'badRequest'}, 400);
    final player = store.get(playerId);
    store.pruneExpired(player, _now());
    final cards = player.cards.values.toList()..sort((a, b) => b.caughtAt.compareTo(a.caughtAt));
    return _json({
      'cards': cards.map((c) => c.toJson()).toList(),
      'caughtSpawnIds': player.caughtSpawns.keys.toList(),
    });
  }

  Future<Response> _track(Request req) async {
    final trackId = req.url.queryParameters['trackId'];
    if (trackId == null) return _json({'error': 'badRequest'}, 400);
    return _json(await catalog.details(trackId));
  }

  Future<Response> _links(Request req) async {
    final q = req.url.queryParameters;
    final trackId = q['trackId'];
    if (trackId == null) return _json({'error': 'badRequest'}, 400);
    return _json(await links.linksFor(
      trackId: trackId,
      title: q['title'] ?? '',
      artist: q['artist'] ?? '',
    ));
  }
}

Response _json(Object body, [int status = 200]) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Lets `flutter run -d chrome` (served from another port) call the API.
Middleware cors() => (inner) => (req) async {
      const headers = {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'GET, POST, OPTIONS',
        'access-control-allow-headers': 'content-type',
      };
      if (req.method == 'OPTIONS') return Response.ok(null, headers: headers);
      final res = await inner(req);
      return res.change(headers: headers);
    };
