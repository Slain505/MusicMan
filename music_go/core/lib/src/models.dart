import 'geo.dart';

enum Rarity {
  common(60),
  uncommon(25),
  rare(10),
  epic(4),
  shiny(1);

  const Rarity(this.weight);

  /// Relative drop weight.
  final int weight;

  static final int _totalWeight =
      Rarity.values.fold(0, (sum, r) => sum + r.weight);

  /// Maps a uniform roll in [0, 1) to a rarity according to [weight].
  static Rarity roll(double u) {
    var acc = 0.0;
    for (final r in Rarity.values) {
      acc += r.weight / _totalWeight;
      if (u < acc) return r;
    }
    return Rarity.values.last;
  }
}

/// Genre "districts" on the map. The server maps each one to a track pool.
enum Genre { pop, hiphop, rock, electronic, rnb, alternative, jazz, classical }

class CellId {
  const CellId(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is CellId && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'CellId($row, $col)';
}

/// A collectible drop on the map. Fully derived from the world seed, the cell
/// and the time window, so it never has to be stored or synced.
class Spawn {
  const Spawn({
    required this.id,
    required this.cell,
    required this.epoch,
    required this.index,
    required this.position,
    required this.rarity,
    required this.genre,
    required this.trackSeed,
    required this.expiresAt,
  });

  final String id;
  final CellId cell;
  final int epoch;
  final int index;
  final GeoPoint position;
  final Rarity rarity;
  final Genre genre;

  /// Server uses this to pick a concrete track from the genre pool.
  final int trackSeed;
  final DateTime expiresAt;

  static String makeId(CellId cell, int epoch, int index) =>
      '${cell.row}_${cell.col}_${epoch}_$index';

  /// Returns (cell, epoch, index) or null when [id] is malformed.
  static (CellId, int, int)? parseId(String id) {
    final parts = id.split('_');
    if (parts.length != 4) return null;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return null;
    return (CellId(nums[0]!, nums[1]!), nums[2]!, nums[3]!);
  }
}

/// A collected track. Preview URLs expire, so only stable metadata is stored;
/// fresh previews and streaming links are fetched on demand.
class TrackCard {
  const TrackCard({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.genre,
    required this.rarity,
    required this.spawnId,
    required this.caughtAt,
    this.count = 1,
  });

  final String trackId;
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final Genre genre;
  final Rarity rarity;
  final String spawnId;
  final DateTime caughtAt;

  /// How many times this exact track + rarity was caught.
  final int count;

  String get collectionKey => '$trackId:${rarity.name}';

  TrackCard copyWith({int? count, DateTime? caughtAt}) => TrackCard(
        trackId: trackId,
        title: title,
        artist: artist,
        album: album,
        coverUrl: coverUrl,
        genre: genre,
        rarity: rarity,
        spawnId: spawnId,
        caughtAt: caughtAt ?? this.caughtAt,
        count: count ?? this.count,
      );

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'album': album,
        'coverUrl': coverUrl,
        'genre': genre.name,
        'rarity': rarity.name,
        'spawnId': spawnId,
        'caughtAt': caughtAt.toUtc().toIso8601String(),
        'count': count,
      };

  factory TrackCard.fromJson(Map<String, dynamic> json) => TrackCard(
        trackId: json['trackId'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String? ?? '',
        coverUrl: json['coverUrl'] as String? ?? '',
        genre: Genre.values.byName(json['genre'] as String),
        rarity: Rarity.values.byName(json['rarity'] as String),
        spawnId: json['spawnId'] as String,
        caughtAt: DateTime.parse(json['caughtAt'] as String),
        count: json['count'] as int? ?? 1,
      );
}

/// Last server-confirmed position of a player, used for speed checks.
class PlayerTrace {
  const PlayerTrace(this.position, this.at);

  final GeoPoint position;
  final DateTime at;
}
