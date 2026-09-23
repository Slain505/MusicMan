import 'package:music_go_core/music_go_core.dart';
import 'package:test/test.dart';

const berlin = GeoPoint(52.5200, 13.4050);
final noon = DateTime.utc(2026, 9, 23, 12);

/// Fingerprint of every spawn around a point. Must be identical on the VM and
/// in the browser (`dart test -p chrome`), otherwise players would see
/// different worlds.
int fingerprint(List<Spawn> spawns) => hashInts([
      for (final s in spawns) ...[
        s.cell.row,
        s.cell.col,
        s.epoch,
        s.index,
        s.rarity.index,
        s.genre.index,
        s.trackSeed,
        (s.position.lat * 1e6).round(),
        (s.position.lng * 1e6).round(),
      ]
    ]);

void main() {
  group('rng', () {
    test('imul32 matches exact big-int math', () {
      final rng = Rng(42);
      final m = BigInt.from(0xFFFFFFFF);
      for (var i = 0; i < 2000; i++) {
        final a = rng.nextUint32(), b = rng.nextUint32();
        final expected = (BigInt.from(a) * BigInt.from(b)) & m;
        expect(imul32(a, b), expected.toInt(), reason: '$a * $b');
      }
    });

    test('hashInts handles negative values and stays 32-bit', () {
      final h = hashInts([-5, 7, -123456789]);
      expect(h, inInclusiveRange(0, 0xFFFFFFFF));
      expect(h, isNot(hashInts([5, 7, -123456789])));
    });

    test('nextDouble is in [0, 1)', () {
      final rng = Rng(1);
      for (var i = 0; i < 10000; i++) {
        expect(rng.nextDouble(), allOf(greaterThanOrEqualTo(0), lessThan(1)));
      }
    });
  });

  group('spawns', () {
    final gen = SpawnGenerator(const SpawnConfig());

    test('are deterministic and platform independent', () {
      final spawns = gen.spawnsNear(berlin, 800, noon);
      expect(spawns, isNotEmpty);
      expect(fingerprint(spawns), fingerprint(gen.spawnsNear(berlin, 800, noon)));
      // Golden value: produced on the Dart VM, must match on the web.
      expect(fingerprint(spawns), goldenFingerprint);
    });

    test('findSpawn regenerates the same spawn from its id', () {
      for (final s in gen.spawnsNear(berlin, 500, noon)) {
        final found = gen.findSpawn(s.id, noon)!;
        expect(found.position.lat, s.position.lat);
        expect(found.position.lng, s.position.lng);
        expect(found.rarity, s.rarity);
        expect(found.trackSeed, s.trackSeed);
      }
    });

    test('spawns stay inside their cell', () {
      for (final s in gen.spawnsNear(berlin, 1000, noon)) {
        expect(gen.cellAt(s.position), s.cell);
      }
    });

    test('expire after their window (with grace)', () {
      final s = gen.spawnsNear(berlin, 500, noon).first;
      expect(gen.findSpawn(s.id, s.expiresAt.subtract(const Duration(seconds: 1))), isNotNull);
      expect(gen.findSpawn(s.id, s.expiresAt.add(const Duration(seconds: 10))), isNotNull);
      expect(gen.findSpawn(s.id, s.expiresAt.add(const Duration(minutes: 2))), isNull);
    });

    test('rejects malformed ids', () {
      expect(gen.findSpawn('nope', noon), isNull);
      expect(gen.findSpawn('1_2_x_0', noon), isNull);
      expect(gen.findSpawn('1_2_3_99', noon), isNull);
    });

    test('density varies across the map but never hits zero', () {
      final densities = [
        for (var r = 0; r < 60; r++) gen.densityAt(CellId(260000 + r * 3, 5000)),
      ];
      final min = densities.reduce((a, b) => a < b ? a : b);
      final max = densities.reduce((a, b) => a > b ? a : b);
      expect(min, greaterThanOrEqualTo(const SpawnConfig().minDensity));
      expect(max - min, greaterThan(0.2));
    });

    test('rarity distribution roughly follows weights', () {
      final counts = {for (final r in Rarity.values) r: 0};
      final rng = Rng(7);
      for (var i = 0; i < 100000; i++) {
        final r = Rarity.roll(rng.nextDouble());
        counts[r] = counts[r]! + 1;
      }
      expect(counts[Rarity.common]! / 100000, closeTo(0.60, 0.02));
      expect(counts[Rarity.shiny]! / 100000, closeTo(0.01, 0.005));
    });
  });

  group('catch validator', () {
    final gen = SpawnGenerator(const SpawnConfig());
    final validator = CatchValidator(gen);
    final spawn = gen.spawnsNear(berlin, 500, noon).first;

    test('accepts a player standing on the spawn', () {
      final r = validator.check(spawnId: spawn.id, position: spawn.position, now: noon);
      expect(r.ok, isTrue);
    });

    test('rejects a player too far away', () {
      final r = validator.check(
          spawnId: spawn.id, position: spawn.position.offsetMeters(100, 0), now: noon);
      expect(r.rejection, CatchRejection.tooFar);
    });

    test('rejects teleports', () {
      final r = validator.check(
        spawnId: spawn.id,
        position: spawn.position,
        now: noon,
        // 5 km away 10 seconds ago = 500 m/s.
        lastTrace: PlayerTrace(spawn.position.offsetMeters(5000, 0),
            noon.subtract(const Duration(seconds: 10))),
      );
      expect(r.rejection, CatchRejection.tooFast);
    });

    test('allows walking between catches', () {
      final r = validator.check(
        spawnId: spawn.id,
        position: spawn.position,
        now: noon,
        lastTrace: PlayerTrace(spawn.position.offsetMeters(300, 0),
            noon.subtract(const Duration(minutes: 4))),
      );
      expect(r.ok, isTrue);
    });

    test('rejects duplicates and unknown spawns', () {
      expect(
          validator
              .check(spawnId: spawn.id, position: spawn.position, now: noon, alreadyCaught: true)
              .rejection,
          CatchRejection.alreadyCaught);
      expect(validator.check(spawnId: 'bad', position: berlin, now: noon).rejection,
          CatchRejection.notFound);
    });
  });
}

const goldenFingerprint = 2363450549;
