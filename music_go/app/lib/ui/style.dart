import 'package:flutter/material.dart';
import 'package:music_go_core/music_go_core.dart';

extension RarityStyle on Rarity {
  Color get color => switch (this) {
        Rarity.common => const Color(0xFF9AA4B2),
        Rarity.uncommon => const Color(0xFF3FC380),
        Rarity.rare => const Color(0xFF3D8BFF),
        Rarity.epic => const Color(0xFFB45CFF),
        Rarity.shiny => const Color(0xFFFFC53D),
      };

  String get label => switch (this) {
        Rarity.common => 'Обычный',
        Rarity.uncommon => 'Необычный',
        Rarity.rare => 'Редкий',
        Rarity.epic => 'Эпический',
        Rarity.shiny => 'Сияющий',
      };
}

extension GenreStyle on Genre {
  IconData get icon => switch (this) {
        Genre.pop => Icons.star_rounded,
        Genre.hiphop => Icons.mic_rounded,
        Genre.rock => Icons.electric_bolt_rounded,
        Genre.electronic => Icons.graphic_eq_rounded,
        Genre.rnb => Icons.favorite_rounded,
        Genre.alternative => Icons.album_rounded,
        Genre.jazz => Icons.nightlife_rounded,
        Genre.classical => Icons.piano_rounded,
      };

  String get label => switch (this) {
        Genre.pop => 'Поп',
        Genre.hiphop => 'Хип-хоп',
        Genre.rock => 'Рок',
        Genre.electronic => 'Электроника',
        Genre.rnb => 'R&B',
        Genre.alternative => 'Альтернатива',
        Genre.jazz => 'Джаз',
        Genre.classical => 'Классика',
      };
}

String rejectionMessage(String reason, double? distance) => switch (reason) {
      'tooFar' => 'Слишком далеко: ${distance?.round() ?? '?'} м. Подойди ближе.',
      'tooFast' => 'Подозрительно быстро переместился. Похоже на подмену GPS.',
      'alreadyCaught' => 'Этот дроп уже пойман.',
      'notFound' => 'Дроп исчез: время вышло.',
      _ => 'Нет связи с сервером.',
    };
