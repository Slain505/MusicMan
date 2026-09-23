import 'dart:io';

import 'package:args/args.dart';
import 'package:music_go_core/music_go_core.dart';
import 'package:music_go_server/music_go_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';

Future<void> main(List<String> args) async {
  final options = (ArgParser()
        ..addOption('port', defaultsTo: '8080')
        ..addOption('web', defaultsTo: '../app/build/web', help: 'Built Flutter web app to serve')
        ..addOption('data', defaultsTo: 'data/players.json')
        ..addFlag('dev', help: 'Relax anti-cheat: allow teleporting in the simulator'))
      .parse(args);

  final dev = options.flag('dev');
  final config = SpawnConfig(maxSpeedMps: dev ? 100000 : 40);

  final store = PlayerStore(File(options.option('data')!));
  await store.load();

  final api = GameApi(
    config: config,
    store: store,
    catalog: MusicCatalog(),
    links: StreamingLinks(apiKey: Platform.environment['ODESLI_API_KEY']),
  );

  var cascade = Cascade().add(api.router.call);
  final webDir = Directory(options.option('web')!);
  if (webDir.existsSync()) {
    cascade = cascade.add(createStaticHandler(webDir.path, defaultDocument: 'index.html'));
  }

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(cors())
      .addHandler(cascade.handler);

  final server = await io.serve(handler, InternetAddress.anyIPv4, int.parse(options.option('port')!));
  stdout.writeln('Music GO server on http://localhost:${server.port}'
      '${dev ? '  [dev: anti-cheat relaxed]' : ''}');
  stdout.writeln(webDir.existsSync()
      ? 'Serving web app from ${webDir.absolute.path}'
      : 'No web build at ${webDir.path} (API only). Run `flutter build web` in app/.');
}
