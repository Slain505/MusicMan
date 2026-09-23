import 'package:flutter/material.dart';
import 'package:music_go_core/music_go_core.dart';

import '../game_controller.dart';
import 'card_sheet.dart';
import 'style.dart';

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key, required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final cards = game.cards;
        final byRarity = {for (final r in Rarity.values) r: cards.where((c) => c.rarity == r).length};
        return Scaffold(
          appBar: AppBar(title: Text('Коллекция · ${cards.length}')),
          body: cards.isEmpty
              ? const Center(child: Text('Пока пусто. Иди гулять 🎧'))
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(spacing: 8, children: [
                      for (final r in Rarity.values.reversed)
                        if (byRarity[r]! > 0)
                          Chip(
                            label: Text('${r.label}: ${byRarity[r]}'),
                            side: BorderSide(color: r.color),
                          ),
                    ]),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: cards.length,
                      itemBuilder: (context, i) => _CardTile(
                        card: cards[i],
                        onTap: () => showCardSheet(context, game.api, cards[i]),
                      ),
                    ),
                  ),
                ]),
        );
      },
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.card, required this.onTap});

  final TrackCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = card.rarity.color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c, width: 2),
          color: c.withValues(alpha: 0.08),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                child: card.coverUrl.isEmpty
                    ? Icon(card.genre.icon, size: 48, color: c)
                    : Image.network(card.coverUrl,
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                        errorBuilder: (_, _, _) => Icon(card.genre.icon, size: 48, color: c)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(card.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${card.artist}${card.count > 1 ? '  ×${card.count}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
