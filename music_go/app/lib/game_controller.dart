import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:music_go_core/music_go_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

enum LocationMode {
  /// Real GPS.
  gps,

  /// Click / arrow keys to move. For testing on a desktop.
  simulator,
}

/// All game state for the map screen.
///
/// Battery rules: no polling. Spawns are recomputed only after moving
/// [_recomputeDistanceM] or when the next spawn expires (a single timer), and
/// GPS uses a distance filter so the OS wakes us only on real movement.
class GameController extends ChangeNotifier {
  GameController(this.api);

  final ApiClient api;

  static const defaultPosition = GeoPoint(52.5200, 13.4050); // Berlin
  static const visibleRadiusM = 600.0;
  static const _recomputeDistanceM = 60.0;
  static const walkSpeedMps = 8.0;

  late SpawnConfig config;
  late SpawnGenerator _generator;
  late CatchValidator validator;
  late String playerId;

  GeoPoint position = defaultPosition;
  LocationMode mode = LocationMode.simulator;
  List<Spawn> spawns = [];
  Set<String> caughtSpawnIds = {};
  List<TrackCard> cards = [];
  String? error;
  bool ready = false;

  GeoPoint? walkTarget;
  GeoPoint? _spawnsComputedAt;
  Timer? _expiryTimer;
  Timer? _walkTimer;
  StreamSubscription<Position>? _gpsSub;

  Future<void> init() async {
    try {
      config = await api.config();
    } catch (e) {
      error = 'Сервер недоступен (${api.baseUrl}). Запусти server: dart run bin/server.dart';
      notifyListeners();
      return;
    }
    _generator = SpawnGenerator(config);
    validator = CatchValidator(_generator);
    playerId = await _loadPlayerId();

    // Start the simulator at the real location when the browser allows it.
    final real = await _currentGps();
    if (real != null) position = real;
    _recomputeSpawns(force: true);
    await refreshCollection();
    ready = true;
    notifyListeners();
  }

  Future<String> _loadPlayerId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('playerId');
    if (id == null) {
      final r = math.Random.secure();
      id = List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join();
      await prefs.setString('playerId', id);
    }
    return id;
  }

  Future<void> refreshCollection() async {
    try {
      final (c, caught) = await api.collection(playerId);
      cards = c;
      caughtSpawnIds = caught;
      notifyListeners();
    } catch (_) {}
  }

  List<Spawn> get visibleSpawns =>
      spawns.where((s) => !caughtSpawnIds.contains(s.id)).toList();

  double distanceTo(Spawn s) => position.distanceTo(s.position);

  // ---- movement --------------------------------------------------------

  void _moveTo(GeoPoint p) {
    position = p;
    _recomputeSpawns();
    notifyListeners();
  }

  /// Simulator: walk towards [target] at [walkSpeedMps].
  void walkTo(GeoPoint target) {
    if (mode != LocationMode.simulator) return;
    walkTarget = target;
    _walkTimer?.cancel();
    const tick = Duration(milliseconds: 100);
    _walkTimer = Timer.periodic(tick, (t) {
      final remaining = position.distanceTo(target);
      final step = walkSpeedMps * tick.inMilliseconds / 1000;
      if (remaining <= step) {
        t.cancel();
        walkTarget = null;
        _moveTo(target);
        return;
      }
      final f = step / remaining;
      _moveTo(GeoPoint(position.lat + (target.lat - position.lat) * f,
          position.lng + (target.lng - position.lng) * f));
    });
  }

  /// Simulator: instant jump. The server treats this like GPS spoofing unless
  /// it runs with `--dev`.
  void teleport(GeoPoint target) {
    if (mode != LocationMode.simulator) return;
    _walkTimer?.cancel();
    walkTarget = null;
    _moveTo(target);
  }

  void step(double northM, double eastM) {
    if (mode != LocationMode.simulator) return;
    _walkTimer?.cancel();
    walkTarget = null;
    _moveTo(position.offsetMeters(northM, eastM));
  }

  Future<void> setMode(LocationMode m) async {
    if (m == mode) return;
    mode = m;
    _walkTimer?.cancel();
    walkTarget = null;
    await _gpsSub?.cancel();
    _gpsSub = null;
    if (m == LocationMode.gps) {
      if (!await _ensurePermission()) {
        mode = LocationMode.simulator;
        error = 'Нет доступа к геолокации';
      } else {
        _gpsSub = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5, // metres; the OS stays quiet while standing still
          ),
        ).listen((p) => _moveTo(GeoPoint(p.latitude, p.longitude)));
      }
    }
    notifyListeners();
  }

  Future<bool> _ensurePermission() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<GeoPoint?> _currentGps() async {
    if (!await _ensurePermission()) return null;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 6)),
      );
      return GeoPoint(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  // ---- spawns ----------------------------------------------------------

  void _recomputeSpawns({bool force = false}) {
    final last = _spawnsComputedAt;
    if (!force && last != null && last.distanceTo(position) < _recomputeDistanceM) return;
    _spawnsComputedAt = position;
    // Generate a bit wider than visible so walking doesn't pop markers in.
    spawns = _generator.spawnsNear(
        position, visibleRadiusM + _recomputeDistanceM, DateTime.now().toUtc());
    _scheduleExpiryRefresh();
  }

  void _scheduleExpiryRefresh() {
    _expiryTimer?.cancel();
    if (spawns.isEmpty) return;
    final next = spawns.map((s) => s.expiresAt).reduce((a, b) => a.isBefore(b) ? a : b);
    final wait = next.difference(DateTime.now().toUtc()) + const Duration(seconds: 1);
    _expiryTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _recomputeSpawns(force: true);
      notifyListeners();
    });
  }

  // ---- catching ----------------------------------------------------------

  /// Checks locally first (instant feedback, no network), then asks the
  /// server, whose answer is final.
  Future<CatchResult> tryCatch(Spawn spawn) async {
    final local = validator.check(
      spawnId: spawn.id,
      position: position,
      now: DateTime.now().toUtc(),
      alreadyCaught: caughtSpawnIds.contains(spawn.id),
    );
    if (!local.ok) throw CatchFailed(local.rejection!.name, local.distanceMeters);

    final result = await api.catchSpawn(playerId, spawn.id, position);
    caughtSpawnIds.add(spawn.id);
    final i = cards.indexWhere((c) => c.collectionKey == result.card.collectionKey);
    if (i >= 0) cards.removeAt(i);
    cards.insert(0, result.card);
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _walkTimer?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }
}
