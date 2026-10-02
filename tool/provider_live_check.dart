// ignore_for_file: avoid_print
import 'dart:io';

import 'package:nex_music/music_data.dart';
import 'package:nex_music/music_provider.dart';

/// Live check: for each provider, loads featured + search results, resolves
/// stream URLs and reads byte ranges at the start, middle and end of each
/// file with the same headers the app's player sends.
Future<void> main(List<String> args) async {
  final perList = args.isEmpty ? 5 : int.parse(args.first);
  final providers = <MusicProvider>[
    JioSaavnProvider(),
    YouTubeMusicProvider(),
    YouTubeVideoProvider(),
  ];
  for (final provider in providers) {
    print('== ${provider.displayName}');
    for (final entry in {
      'featured': () => provider.loadFeatured(limit: perList),
      'search': () => provider.searchSongs('Arijit Singh', limit: perList),
    }.entries) {
      List<Song> songs;
      try {
        songs = await entry.value();
      } catch (error) {
        print('  ${entry.key}: LIST FAIL $error');
        continue;
      }
      var passed = 0;
      for (final song in songs) {
        final result = await _check(provider, song);
        if (result == null) {
          passed++;
        } else {
          print('  FAIL ${entry.key} "${song.title}": $result');
        }
      }
      print('  ${entry.key}: $passed/${songs.length} fully readable');
    }
  }
}

Future<String?> _check(MusicProvider provider, Song song) async {
  final String url;
  try {
    url = await provider.resolveStreamUrl(song);
  } catch (error) {
    return 'resolve: $error';
  }
  final headers = provider.playbackHeaders(song);
  final client = HttpClient();
  try {
    final first = await _range(client, url, headers, 0, 255);
    if (first.$1 != 206 && first.$1 != 200) return 'start HTTP ${first.$1}';
    final total = first.$2;
    if (total == null || total <= 0) return null;
    for (final offset in [total ~/ 2, total - 256]) {
      final result = await _range(client, url, headers, offset, offset + 255);
      if (result.$1 != 206) return 'offset $offset/$total HTTP ${result.$1}';
    }
    return null;
  } catch (error) {
    return 'read: $error';
  } finally {
    client.close(force: true);
  }
}

Future<(int, int?)> _range(
  HttpClient client,
  String url,
  Map<String, String> headers,
  int start,
  int end,
) async {
  final request = await client.getUrl(Uri.parse(url));
  headers.forEach(request.headers.set);
  request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
  final response = await request.close();
  final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
  await response.drain<void>();
  final total = contentRange == null
      ? null
      : int.tryParse(contentRange.split('/').last);
  return (response.statusCode, total);
}
