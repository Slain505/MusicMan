import 'dart:math' as math;

import 'geo.dart';
import 'models.dart';
import 'noise.dart';
import 'rng.dart';

class SpawnConfig {
  const SpawnConfig({
    this.worldSeed = 1337,
    this.cellSizeMeters = 200,
    this.epochDuration = const Duration(minutes: 20),
    this.maxSpawnsPerCell = 4,
    this.minDensity = 0.15,
    this.densityScaleCells = 8,
    this.genreDistrictCells = 10,
    this.catchRadiusMeters = 40,
    this.maxSpeedMps = 40,
  });

  /// Changing the seed reshuffles the whole world.
  final int worldSeed;
  final double cellSizeMeters;

  /// How long a cell keeps the same spawns before they rotate.
  final Duration epochDuration;
  final int maxSpawnsPerCell;

  /// Density floor in [0, 1] so sparse areas never end up empty.
  final double minDensity;

  /// Size (in cells) of dense / sparse blobs.
  final double densityScaleCells;

  /// Side (in cells) of a square genre district.
  final int genreDistrictCells;
  final double catchRadiusMeters;

  /// Anything faster between two catches is treated as GPS spoofing.
  final double maxSpeedMps;

  Map<String, dynamic> toJson() => {
        'worldSeed': worldSeed,
        'cellSizeMeters': cellSizeMeters,
        'epochMinutes': epochDuration.inMinutes,
        'maxSpawnsPerCell': maxSpawnsPerCell,
        'minDensity': minDensity,
        'densityScaleCells': densityScaleCells,
        'genreDistrictCells': genreDistrictCells,
        'catchRadiusMeters': catchRadiusMeters,
        'maxSpeedMps': maxSpeedMps,
      };

  factory SpawnConfig.fromJson(Map<String, dynamic> j) => SpawnConfig(
        worldSeed: j['worldSeed'] as int,
        cellSizeMeters: (j['cellSizeMeters'] as num).toDouble(),
        epochDuration: Duration(minutes: j['epochMinutes'] as int),
        maxSpawnsPerCell: j['maxSpawnsPerCell'] as int,
        minDensity: (j['minDensity'] as num).toDouble(),
        densityScaleCells: (j['densityScaleCells'] as num).toDouble(),
        genreDistrictCells: j['genreDistrictCells'] as int,
        catchRadiusMeters: (j['catchRadiusMeters'] as num).toDouble(),
        maxSpeedMps: (j['maxSpeedMps'] as num).toDouble(),
      );
}

/// Turns (world seed, grid cell, time window) into spawns.
///
/// The world is a grid of rows of equal latitude height; each row has its own
/// longitude step so cells stay roughly square at any latitude. Nothing is
/// stored: client and server regenerate the same spawns on demand.
class SpawnGenerator {
  SpawnGenerator(this.config)
      : _dLat = config.cellSizeMeters / metersPerDegreeLat;

  final SpawnConfig config;
  final double _dLat;

  int get _seed => config.worldSeed;
  int get _epochMs => config.epochDuration.inMilliseconds;

  CellId cellAt(GeoPoint p) {
    final row = (p.lat / _dLat).floor();
    return CellId(row, (p.lng / _dLngForRow(row)).floor());
  }

  double _dLngForRow(int row) =>
      config.cellSizeMeters / metersPerDegreeLng((row + 0.5) * _dLat);

  /// Cells rotate at staggered times so the whole map never refreshes at once.
  int _epochOffsetMs(CellId c) => hashInts([c.row, c.col, 0xE0], _seed) % _epochMs;

  int epochFor(CellId c, DateTime t) =>
      ((t.millisecondsSinceEpoch + _epochOffsetMs(c)) / _epochMs).floor();

  DateTime epochEnd(CellId c, int epoch) => DateTime.fromMillisecondsSinceEpoch(
      (epoch + 1) * _epochMs - _epochOffsetMs(c),
      isUtc: true);

  /// Density in [minDensity, 1] for a cell.
  double densityAt(CellId c) {
    final n = fractalNoise(
        c.row / config.densityScaleCells, c.col / config.densityScaleCells, _seed ^ 0xD3);
    return config.minDensity + (1 - config.minDensity) * n;
  }

  Genre districtGenre(CellId c) {
    final size = config.genreDistrictCells;
    final h = hashInts([(c.row / size).floor(), (c.col / size).floor()], _seed ^ 0x6E);
    return Genre.values[h % Genre.values.length];
  }

  List<Spawn> spawnsInCell(CellId c, DateTime now) =>
      _generate(c, epochFor(c, now));

  List<Spawn> _generate(CellId c, int epoch) {
    final rng = Rng(hashInts([c.row, c.col, epoch], _seed));
    // floor(x + u) has expected value x, so average count == density * max.
    final count = (densityAt(c) * config.maxSpawnsPerCell + rng.nextDouble())
        .floor()
        .clamp(0, config.maxSpawnsPerCell);
    final dLng = _dLngForRow(c.row);
    final district = districtGenre(c);
    final expiresAt = epochEnd(c, epoch);

    return List.generate(count, (i) {
      final lat = (c.row + rng.nextDouble()) * _dLat;
      final lng = (c.col + rng.nextDouble()) * dLng;
      final rarity = Rarity.roll(rng.nextDouble());
      // Mostly the district's genre, sometimes a surprise.
      final genre = rng.nextDouble() < 0.75
          ? district
          : Genre.values[rng.nextInt(Genre.values.length)];
      return Spawn(
        id: Spawn.makeId(c, epoch, i),
        cell: c,
        epoch: epoch,
        index: i,
        position: GeoPoint(lat, lng),
        rarity: rarity,
        genre: genre,
        trackSeed: rng.nextUint32(),
        expiresAt: expiresAt,
      );
    });
  }

  /// All spawns within [radiusMeters] of [center].
  List<Spawn> spawnsNear(GeoPoint center, double radiusMeters, DateTime now) {
    final southWest = center.offsetMeters(-radiusMeters, -radiusMeters);
    final northEast = center.offsetMeters(radiusMeters, radiusMeters);
    final rowMin = (southWest.lat / _dLat).floor();
    final rowMax = (northEast.lat / _dLat).floor();
    final result = <Spawn>[];
    for (var row = rowMin; row <= rowMax; row++) {
      final dLng = _dLngForRow(row);
      final colMin = (southWest.lng / dLng).floor();
      final colMax = (northEast.lng / dLng).floor();
      for (var col = colMin; col <= colMax; col++) {
        for (final s in spawnsInCell(CellId(row, col), now)) {
          if (s.position.distanceTo(center) <= radiusMeters) result.add(s);
        }
      }
    }
    return result;
  }

  /// Regenerates a spawn from its id. Returns null when the id is malformed,
  /// refers to a spawn that doesn't exist, or its time window is over (a
  /// small [grace] covers clock skew and slow networks).
  Spawn? findSpawn(String id, DateTime now,
      {Duration grace = const Duration(seconds: 30)}) {
    final parsed = Spawn.parseId(id);
    if (parsed == null) return null;
    final (cell, epoch, index) = parsed;
    final current = epochFor(cell, now);
    final stillValid = epoch == current ||
        (epoch == current - 1 && now.isBefore(epochEnd(cell, epoch).add(grace)));
    if (!stillValid) return null;
    final spawns = _generate(cell, epoch);
    return index >= 0 && index < spawns.length ? spawns[index] : null;
  }

  /// Rough spawn count per km², handy for tuning.
  double averageSpawnsPerKm2() =>
      (config.minDensity + (1 - config.minDensity) * 0.5) *
      config.maxSpawnsPerCell *
      1e6 /
      math.pow(config.cellSizeMeters, 2);
}
