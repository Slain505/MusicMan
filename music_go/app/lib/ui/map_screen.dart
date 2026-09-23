import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:music_go_core/music_go_core.dart';

import '../api_client.dart';
import '../game_controller.dart';
import 'card_sheet.dart';
import 'collection_screen.dart';
import 'style.dart';

LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lng);
GeoPoint _gp(LatLng p) => GeoPoint(p.latitude, p.longitude);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.game});

  final GameController game;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  bool _follow = true;
  bool _mapReady = false;
  String? _catching;

  GameController get game => widget.game;

  @override
  void initState() {
    super.initState();
    game.addListener(_onGame);
  }

  @override
  void dispose() {
    game.removeListener(_onGame);
    super.dispose();
  }

  void _onGame() {
    if (_follow && _mapReady) _map.move(_ll(game.position), _map.camera.zoom);
  }

  Future<void> _catch(Spawn spawn) async {
    if (_catching != null) return;
    setState(() => _catching = spawn.id);
    try {
      final r = await game.tryCatch(spawn);
      if (mounted) await showCardSheet(context, game.api, r.card, isNew: r.isNew);
    } on CatchFailed catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(rejectionMessage(e.reason, e.distanceMeters))));
      }
    } finally {
      if (mounted) setState(() => _catching = null);
    }
  }

  Map<ShortcutActivator, VoidCallback> get _keys {
    const d = 15.0;
    return {
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => game.step(d, 0),
      const SingleActivator(LogicalKeyboardKey.keyW): () => game.step(d, 0),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => game.step(-d, 0),
      const SingleActivator(LogicalKeyboardKey.keyS): () => game.step(-d, 0),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => game.step(0, -d),
      const SingleActivator(LogicalKeyboardKey.keyA): () => game.step(0, -d),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => game.step(0, d),
      const SingleActivator(LogicalKeyboardKey.keyD): () => game.step(0, d),
    };
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _keys,
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: game,
          builder: (context, _) => Scaffold(
            body: Stack(children: [
              _buildMap(),
              Positioned(top: 12, left: 12, right: 12, child: SafeArea(child: _TopBar(game: game))),
              if (game.mode == LocationMode.simulator)
                const Positioned(left: 12, bottom: 12, child: _SimHint()),
            ]),
            floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
              FloatingActionButton.small(
                heroTag: 'follow',
                tooltip: 'Следовать за игроком',
                onPressed: () {
                  setState(() => _follow = true);
                  _map.move(_ll(game.position), 17);
                },
                child: Icon(_follow ? Icons.my_location : Icons.location_searching),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'collection',
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CollectionScreen(game: game))),
                icon: const Icon(Icons.library_music_rounded),
                label: Text('${game.cards.length}'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    final radius = game.config.catchRadiusMeters;
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _ll(game.position),
        initialZoom: 17,
        minZoom: 13,
        maxZoom: 19,
        onMapReady: () => _mapReady = true,
        onPositionChanged: (_, hasGesture) {
          if (hasGesture && _follow) setState(() => _follow = false);
        },
        onTap: (_, p) => game.walkTo(_gp(p)),
        onLongPress: (_, p) => game.teleport(_gp(p)),
      ),
      children: [
        // OSM's public tiles are fine for development only; use MapTiler,
        // Stadia or self-hosted tiles before release.
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'dev.musicgo.app',
          tileBuilder: darkModeTileBuilder,
        ),
        CircleLayer(circles: [
          CircleMarker(
            point: _ll(game.position),
            radius: radius,
            useRadiusInMeter: true,
            color: Colors.cyanAccent.withValues(alpha: 0.08),
            borderColor: Colors.cyanAccent.withValues(alpha: 0.5),
            borderStrokeWidth: 1.5,
          ),
        ]),
        if (game.walkTarget != null)
          PolylineLayer(polylines: [
            Polyline(
              points: [_ll(game.position), _ll(game.walkTarget!)],
              color: Colors.cyanAccent.withValues(alpha: 0.5),
              strokeWidth: 2,
              pattern: StrokePattern.dashed(segments: const [8, 6]),
            ),
          ]),
        MarkerLayer(markers: [
          for (final s in game.visibleSpawns)
            Marker(
              point: _ll(s.position),
              width: 44,
              height: 44,
              child: _SpawnMarker(
                spawn: s,
                inRange: game.distanceTo(s) <= radius,
                busy: _catching == s.id,
                onTap: () => _catch(s),
              ),
            ),
          Marker(point: _ll(game.position), width: 26, height: 26, child: const _PlayerDot()),
        ]),
        const SimpleAttributionWidget(source: Text('© OpenStreetMap contributors')),
      ],
    );
  }
}

class _SpawnMarker extends StatelessWidget {
  const _SpawnMarker({required this.spawn, required this.inRange, required this.busy, required this.onTap});

  final Spawn spawn;
  final bool inRange;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = spawn.rarity.color;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: inRange ? 1.15 : 0.85,
          duration: const Duration(milliseconds: 200),
          child: Opacity(
            opacity: inRange ? 1 : 0.7,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF151A22),
                border: Border.all(color: c, width: 3),
                boxShadow: [
                  if (inRange || spawn.rarity.index >= Rarity.epic.index)
                    BoxShadow(color: c.withValues(alpha: 0.7), blurRadius: 14),
                ],
              ),
              child: busy
                  ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(spawn.genre.icon, color: c, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerDot extends StatelessWidget {
  const _PlayerDot();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.cyanAccent,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.cyanAccent, blurRadius: 12)],
        ),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final inRange = game.visibleSpawns
        .where((s) => game.distanceTo(s) <= game.config.catchRadiusMeters)
        .length;
    return Card(
      color: const Color(0xE6151A22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          const Icon(Icons.headphones_rounded, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              inRange > 0 ? 'Рядом дропов: $inRange. Жми на них!' : 'Дропов вокруг: ${game.visibleSpawns.length}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SegmentedButton<LocationMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: LocationMode.simulator, icon: Icon(Icons.mouse), tooltip: 'Симулятор'),
              ButtonSegment(value: LocationMode.gps, icon: Icon(Icons.gps_fixed), tooltip: 'Реальный GPS'),
            ],
            selected: {game.mode},
            onSelectionChanged: (s) => game.setMode(s.first),
          ),
        ]),
      ),
    );
  }
}

class _SimHint extends StatelessWidget {
  const _SimHint();

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xCC151A22),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            'Клик: идти туда  ·  WASD/стрелки: шаг 15 м\nДолгий клик: телепорт (сервер сочтёт читом)',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
      );
}
