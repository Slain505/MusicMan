import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:music_go_core/music_go_core.dart';

class PlayerData {
  PlayerData();

  PlayerTrace? lastTrace;

  /// Keyed by [TrackCard.collectionKey].
  final Map<String, TrackCard> cards = {};

  /// Spawn id -> its expiry; pruned once expired.
  final Map<String, DateTime> caughtSpawns = {};

  Map<String, dynamic> toJson() => {
        if (lastTrace != null)
          'lastTrace': {
            ...lastTrace!.position.toJson(),
            'at': lastTrace!.at.toUtc().toIso8601String(),
          },
        'cards': cards.values.map((c) => c.toJson()).toList(),
        'caughtSpawns':
            caughtSpawns.map((id, exp) => MapEntry(id, exp.toUtc().toIso8601String())),
      };

  factory PlayerData.fromJson(Map<String, dynamic> j) {
    final p = PlayerData();
    final t = j['lastTrace'] as Map<String, dynamic>?;
    if (t != null) {
      p.lastTrace = PlayerTrace(GeoPoint.fromJson(t), DateTime.parse(t['at'] as String));
    }
    for (final c in (j['cards'] as List? ?? []).cast<Map<String, dynamic>>()) {
      final card = TrackCard.fromJson(c);
      p.cards[card.collectionKey] = card;
    }
    (j['caughtSpawns'] as Map<String, dynamic>? ?? {})
        .forEach((id, exp) => p.caughtSpawns[id] = DateTime.parse(exp as String));
    return p;
  }
}

/// Dead-simple JSON-file persistence. Good enough for local testing; swap
/// for Postgres/Supabase when going online.
class PlayerStore {
  PlayerStore(this._file);

  final File _file;
  final Map<String, PlayerData> _players = {};
  Timer? _saveTimer;

  Future<void> load() async {
    if (!await _file.exists()) return;
    final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    json.forEach((id, data) => _players[id] = PlayerData.fromJson(data as Map<String, dynamic>));
  }

  PlayerData get(String playerId) => _players.putIfAbsent(playerId, PlayerData.new);

  void pruneExpired(PlayerData p, DateTime now) =>
      p.caughtSpawns.removeWhere((_, exp) => exp.add(const Duration(minutes: 5)).isBefore(now));

  /// Debounced so a burst of catches causes a single write.
  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () async {
      await _file.parent.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_players.map((k, v) => MapEntry(k, v.toJson()))));
      await tmp.rename(_file.path);
    });
  }
}
