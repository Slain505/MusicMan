import 'package:flutter/material.dart';

import 'api_client.dart';
import 'game_controller.dart';
import 'ui/map_screen.dart';

void main() => runApp(const MusicGoApp());

class MusicGoApp extends StatefulWidget {
  const MusicGoApp({super.key});

  @override
  State<MusicGoApp> createState() => _MusicGoAppState();
}

class _MusicGoAppState extends State<MusicGoApp> {
  late final GameController _game = GameController(ApiClient(resolveApiBase()))..init();

  @override
  void dispose() {
    _game.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music GO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.cyan,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
      ),
      home: ListenableBuilder(
        listenable: _game,
        builder: (context, _) {
          if (_game.ready) return MapScreen(game: _game);
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _game.error != null
                    ? Text(_game.error!, textAlign: TextAlign.center)
                    : const CircularProgressIndicator(),
              ),
            ),
          );
        },
      ),
    );
  }
}
