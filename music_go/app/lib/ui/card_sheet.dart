import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_go_core/music_go_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import 'style.dart';

Future<void> showCardSheet(BuildContext context, ApiClient api, TrackCard card,
    {bool isNew = false}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => CardSheet(api: api, card: card, isNew: isNew),
    );

/// A collected track: cover, rarity, 30 s preview and links to services.
class CardSheet extends StatefulWidget {
  const CardSheet({super.key, required this.api, required this.card, this.isNew = false});

  final ApiClient api;
  final TrackCard card;
  final bool isNew;

  @override
  State<CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<CardSheet> {
  final _player = AudioPlayer();
  TrackDetails? _details;
  Map<String, String>? _links;

  @override
  void initState() {
    super.initState();
    widget.api.track(widget.card.trackId).then((d) async {
      if (!mounted) return;
      setState(() => _details = d);
      if (d.previewUrl != null) {
        await _player.setUrl(d.previewUrl!);
        if (widget.isNew) _player.play();
      }
    }).catchError((_) {});
    widget.api.links(widget.card).then((l) {
      if (mounted) setState(() => _links = l);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final rarity = card.rarity;
    final cover = _details?.coverUrl ?? card.coverUrl;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isNew)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('НОВЫЙ ТРЕК!',
                    style: text.labelLarge?.copyWith(color: rarity.color, letterSpacing: 2)),
              ),
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: rarity.color, width: 4),
                boxShadow: [
                  if (rarity.index >= Rarity.rare.index)
                    BoxShadow(color: rarity.color.withValues(alpha: 0.6), blurRadius: 30),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: cover.isEmpty
                  ? Icon(card.genre.icon, size: 96, color: rarity.color)
                  : Image.network(cover,
                      fit: BoxFit.cover,
                      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                      errorBuilder: (_, _, _) => Icon(card.genre.icon, size: 96)),
            ),
            const SizedBox(height: 16),
            Text(card.title,
                style: text.titleLarge, textAlign: TextAlign.center, maxLines: 2),
            Text(card.artist, style: text.titleMedium?.copyWith(color: Colors.white70)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              Chip(
                label: Text(rarity.label),
                backgroundColor: rarity.color.withValues(alpha: 0.2),
                side: BorderSide(color: rarity.color),
              ),
              Chip(avatar: Icon(card.genre.icon, size: 18), label: Text(card.genre.label)),
              if (card.count > 1) Chip(label: Text('×${card.count}')),
            ]),
            const SizedBox(height: 12),
            _PreviewButton(player: _player, available: _details?.previewUrl != null, loading: _details == null),
            const SizedBox(height: 12),
            _LinksRow(links: _links),
          ],
        ),
      ),
    );
  }
}

class _PreviewButton extends StatelessWidget {
  const _PreviewButton({required this.player, required this.available, required this.loading});

  final AudioPlayer player;
  final bool available;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator()));
    if (!available) return const Text('Превью недоступно');
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        final done = snap.data?.processingState == ProcessingState.completed;
        return FilledButton.icon(
          onPressed: () async {
            if (playing && !done) {
              await player.pause();
            } else {
              if (done) await player.seek(Duration.zero);
              await player.play();
            }
          },
          icon: Icon(playing && !done ? Icons.pause_rounded : Icons.play_arrow_rounded),
          label: StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (_, pos) => Text(playing && !done
                ? 'Превью ${pos.data?.inSeconds ?? 0} / 30 с'
                : 'Слушать превью'),
          ),
        );
      },
    );
  }
}

class _LinksRow extends StatelessWidget {
  const _LinksRow({required this.links});

  final Map<String, String>? links;

  static const _services = {
    'spotify': 'Spotify',
    'appleMusic': 'Apple Music',
    'youtube': 'YouTube',
    'youtubeMusic': 'YT Music',
    'deezer': 'Deezer',
  };

  @override
  Widget build(BuildContext context) {
    final l = links;
    if (l == null) return const LinearProgressIndicator();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final e in _services.entries)
          if (l[e.key] != null)
            OutlinedButton(
              onPressed: () => launchUrl(Uri.parse(l[e.key]!), mode: LaunchMode.externalApplication),
              child: Text(e.value),
            ),
      ],
    );
  }
}
