import 'geo.dart';
import 'models.dart';
import 'spawn_generator.dart';

enum CatchRejection {
  /// Unknown id or the spawn's time window is over.
  notFound,
  tooFar,

  /// Moved implausibly fast since the last confirmed catch (GPS spoofing).
  tooFast,
  alreadyCaught,
}

class CatchCheck {
  const CatchCheck._(this.spawn, this.rejection, this.distanceMeters);

  final Spawn? spawn;
  final CatchRejection? rejection;
  final double? distanceMeters;

  bool get ok => rejection == null;
}

/// The single source of truth for "may this player catch this spawn now".
/// The client runs it for instant UI feedback; the server runs it again and
/// its answer is the only one that counts.
class CatchValidator {
  const CatchValidator(this.generator);

  final SpawnGenerator generator;

  CatchCheck check({
    required String spawnId,
    required GeoPoint position,
    required DateTime now,
    PlayerTrace? lastTrace,
    bool alreadyCaught = false,
  }) {
    final spawn = generator.findSpawn(spawnId, now);
    if (spawn == null) return const CatchCheck._(null, CatchRejection.notFound, null);
    if (alreadyCaught) {
      return CatchCheck._(spawn, CatchRejection.alreadyCaught, null);
    }

    final distance = position.distanceTo(spawn.position);
    if (distance > generator.config.catchRadiusMeters) {
      return CatchCheck._(spawn, CatchRejection.tooFar, distance);
    }

    if (lastTrace != null) {
      final moved = lastTrace.position.distanceTo(position);
      final seconds = now.difference(lastTrace.at).inMilliseconds / 1000;
      // Short hops are GPS jitter, not cheating.
      final suspicious = moved > generator.config.catchRadiusMeters &&
          moved / (seconds < 1 ? 1 : seconds) > generator.config.maxSpeedMps;
      if (suspicious) return CatchCheck._(spawn, CatchRejection.tooFast, distance);
    }

    return CatchCheck._(spawn, null, distance);
  }
}
