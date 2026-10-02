// Run explicitly with: flutter test tool/discovery_live_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_music/music_provider.dart';
import 'package:nex_music/music_discovery.dart';

void main() {
  test('live combined discovery and both radio providers', () async {
    final jio = JioSaavnProvider();
    final yt = YouTubeMusicProvider();
    final video = YouTubeVideoProvider();
    final discovery = MusicDiscovery([jio, yt, video]);
    final home = await discovery.browse(limit: 8);
    expect(home.unavailable, isEmpty);
    expect(home.songs.map((s) => s.providerId).toSet(), {
      'jiosaavn',
      'ytmusic',
    });
    final found = await discovery.browse(query: 'Arijit Singh', limit: 4);
    expect(found.songs.map((s) => s.providerId).toSet(), {
      'jiosaavn',
      'ytmusic',
    });
    for (final provider in [jio, yt]) {
      final seed = found.songs.firstWhere((s) => s.providerId == provider.id);
      final radio = await provider.loadRadio(seed.sourceId, limit: 8);
      expect(radio, isNotEmpty, reason: '${provider.displayName} radio');
      final stream = Uri.parse(await provider.resolveStreamUrl(seed));
      expect(stream.scheme, 'https');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        // Check past the first megabyte, where restricted anonymous streams
        // can otherwise appear to start normally and then fail.
        for (final offset in [0, 1500000]) {
          final request = await client.getUrl(stream);
          provider.playbackHeaders(seed).forEach(request.headers.set);
          request.headers.set(
            HttpHeaders.rangeHeader,
            'bytes=$offset-${offset + 127}',
          );
          final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
          expect(
            response.statusCode,
            anyOf(200, 206),
            reason: '${provider.displayName} byte range $offset',
          );
          await response.take(1).drain<void>();
        }
      } finally {
        client.close(force: true);
      }
    }
    expect(
      (await discovery.browse(
        videos: true,
        query: 'Arijit Singh',
        limit: 4,
      )).songs,
      isNotEmpty,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
