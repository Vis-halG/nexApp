import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'music_data.dart';

class LyricLine {
  const LyricLine(this.at, this.text);
  final Duration at;
  final String text;
}

class SongLyrics {
  SongLyrics({required this.plain, this.synced = '', this.instrumental = false})
    : lines = parseLrc(synced);
  final String plain, synced;
  final bool instrumental;
  final List<LyricLine> lines;
  bool get timed => lines.isNotEmpty;
  int activeLine(Duration position) {
    var low = 0, high = lines.length - 1, active = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].at <= position) {
        active = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return active;
  }

  Map<String, dynamic> toJson() => {
    'plainLyrics': plain,
    'syncedLyrics': synced,
    'instrumental': instrumental,
  };
  static SongLyrics fromJson(Map<String, dynamic> json) => SongLyrics(
    plain: json['plainLyrics'] as String? ?? '',
    synced: json['syncedLyrics'] as String? ?? '',
    instrumental: json['instrumental'] == true,
  );
}

List<LyricLine> parseLrc(String input) {
  var offset = 0;
  final offsetMatch = RegExp(
    r'\[offset:([+-]?\d+)\]',
    caseSensitive: false,
  ).firstMatch(input);
  if (offsetMatch != null) offset = int.tryParse(offsetMatch[1]!) ?? 0;
  final timestamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  final lines = <LyricLine>[];
  for (final line in const LineSplitter().convert(input)) {
    final matches = timestamp.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final text = line.replaceAll(timestamp, '').trim();
    for (final match in matches) {
      final minute = int.parse(match[1]!), second = int.parse(match[2]!);
      if (second >= 60) continue;
      final fraction = match[3] ?? '0';
      final millis = int.parse(fraction.padRight(3, '0'));
      lines.add(
        LyricLine(
          Duration(
            milliseconds: (minute * 60000 + second * 1000 + millis + offset)
                .clamp(0, 86400000),
          ),
          text,
        ),
      );
    }
  }
  lines.sort((a, b) => a.at.compareTo(b.at));
  return lines;
}

class MusicLyricsService {
  MusicLyricsService(this.prefs, {Future<dynamic> Function(Uri)? fetch})
    : _fetch = fetch ?? fetchMusicJson;
  final SharedPreferences prefs;
  final Future<dynamic> Function(Uri) _fetch;
  final _pending = <String, Future<SongLyrics>>{};
  Future<SongLyrics> get(
    Song song, {
    String? custom,
    bool refresh = false,
  }) async {
    if (custom != null && custom.isNotEmpty) {
      return SongLyrics(
        plain: custom.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim(),
        synced: custom,
      );
    }
    final key =
        'lyrics:${base64Url.encode(utf8.encode('${song.title}:${song.artist}:${song.durationMs}'))}';
    if (!refresh) {
      try {
        final cache = prefs.getString(key);
        if (cache != null) {
          return SongLyrics.fromJson(jsonDecode(cache) as Map<String, dynamic>);
        }
      } catch (_) {}
    }
    return _pending.putIfAbsent(key, () async {
      try {
        dynamic row;
        if (song.artist.isNotEmpty) {
          try {
            row = await _fetch(
              Uri.https('lrclib.net', '/api/get', {
                'track_name': song.title,
                'artist_name': song.artist,
                if (song.album.isNotEmpty) 'album_name': song.album,
                if (song.durationMs > 0)
                  'duration': '${song.durationMs ~/ 1000}',
              }),
            );
          } catch (_) {}
        }
        if (row is! Map) {
          final results = await _fetch(
            Uri.https('lrclib.net', '/api/search', {
              'q': '${song.title} ${song.artist}'.trim(),
            }),
          );
          if (results is List) {
            String normal(String text) => text.toLowerCase().replaceAll(
              RegExp(r'[\s\p{P}\p{S}]', unicode: true),
              '',
            );
            row = results
                .whereType<Map>()
                .where(
                  (r) =>
                      normal('${r['trackName']}') == normal(song.title) &&
                      (song.artist.isEmpty ||
                          normal('${r['artistName']}') ==
                              normal(song.artist)) &&
                      (song.durationMs == 0 ||
                          (((r['duration'] as num? ?? 0) * 1000) -
                                      song.durationMs)
                                  .abs() <
                              10000),
                )
                .firstOrNull;
          }
        }
        if (row is! Map) {
          throw const FormatException(
            'Lyrics are not available for this recording. You can import an LRC file.',
          );
        }
        final result = SongLyrics.fromJson(Map<String, dynamic>.from(row));
        if (result.plain.isEmpty && !result.timed && !result.instrumental) {
          throw const FormatException('No lyrics found.');
        }
        await prefs.setString(key, jsonEncode(result.toJson()));
        return result;
      } finally {
        _pending.remove(key);
      }
    });
  }
}

/// Bounded HTTPS reads used by catalogue, lyrics and feeds.
Future<dynamic> fetchMusicJson(Uri uri) async =>
    jsonDecode(await fetchMusicText(uri));
Future<String> fetchMusicText(Uri uri, {int maxBytes = 2 * 1024 * 1024}) async {
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    throw const FormatException('Use an HTTPS link.');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(uri);
    request.headers.set('User-Agent', 'nexApp/0.4.0 (music library)');
    final response = await request.close().timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw HttpException('Service returned ${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 25))) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('Response is too large.');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  } finally {
    client.close(force: true);
  }
}
