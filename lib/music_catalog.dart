import 'music_data.dart';
import 'music_provider.dart';
import 'music_discovery.dart';
import 'music_lyrics.dart';

class MusicCatalog {
  MusicCatalog({Future<dynamic> Function(Uri)? fetch})
    : _fetch = fetch ?? fetchMusicJson;
  final Future<dynamic> Function(Uri) _fetch;
  Future<List<Song>> album(Song seed) async {
    if (seed.providerId != 'jiosaavn' || seed.albumId.isEmpty) return [];
    final data = await _fetch(
      Uri.https('www.jiosaavn.com', '/api.php', {
        '__call': 'content.getAlbumDetails',
        'albumid': seed.albumId,
        '_format': 'json',
        '_marker': '0',
        'ctx': 'web6dot0',
      }),
    );
    if (data is! Map || data['songs'] is! List) return [];
    return (data['songs'] as List)
        .whereType<Map>()
        .map(_jioSong)
        .whereType<Song>()
        .toList();
  }

  Song? _jioSong(Map row) {
    final id = '${row['id'] ?? ''}',
        more = row['more_info'] is Map ? row['more_info'] as Map : row;
    final title = decodeHtmlText(row['title'] ?? row['song'] ?? row['name']);
    if (id.isEmpty || title.isEmpty) return null;
    final map = more['artistMap'] as Map?;
    final primary = map?['primary_artists'] as List?;
    final artist =
        primary
            ?.whereType<Map>()
            .map((a) => decodeHtmlText(a['name']))
            .join(', ') ??
        decodeHtmlText(more['music'] ?? row['singers']);
    return Song(
      id: 'provider:jiosaavn:$id',
      sourceId: id,
      providerId: 'jiosaavn',
      kind: 'audio',
      url: '',
      title: title,
      artist: artist,
      artworkUrl: '${row['image'] ?? ''}'.replaceAll('150x150', '500x500'),
      album: decodeHtmlText(more['album'] ?? row['album']),
      albumId: '${more['album_id'] ?? ''}',
      language: '${more['language'] ?? ''}',
      durationMs: (int.tryParse('${more['duration'] ?? 0}') ?? 0) * 1000,
    );
  }
}

/// Prompt parsing remains deterministic and inspectable; no API credentials required.
class MusicPrompt {
  MusicPrompt(
    this.query, {
    this.language = 'Any',
    this.mood = 'Any',
    this.limit = 20,
  });
  final String query, language, mood;
  final int limit;
  static MusicPrompt parse(String input) {
    final value = input.trim();
    if (value.isEmpty || value.length > 300) {
      throw const FormatException(
        'Describe your playlist in 1–300 characters.',
      );
    }
    final lower = value.toLowerCase();
    const languages = {
      'hindi': 'Hindi',
      'punjabi': 'Punjabi',
      'bhojpuri': 'Bhojpuri',
      'tamil': 'Tamil',
      'telugu': 'Telugu',
      'bengali': 'Bengali',
      'marathi': 'Marathi',
      'english': 'English',
      'kannada': 'Kannada',
      'malayalam': 'Malayalam',
      'gujarati': 'Gujarati',
    };
    const moods = {
      'rain': 'Rainy',
      'baarish': 'Rainy',
      'workout': 'Workout',
      'gym': 'Workout',
      'sleep': 'Sleep',
      'raat': 'Night',
      'night': 'Night',
      'sad': 'Sad',
      'romantic': 'Romantic',
      'love': 'Romantic',
      'party': 'Party',
      'focus': 'Focus',
      'study': 'Focus',
      'travel': 'Travel',
      'drive': 'Travel',
      'bhajan': 'Devotional',
      'devotional': 'Devotional',
    };
    final language =
        languages.entries
            .where((e) => lower.contains(e.key))
            .map((e) => e.value)
            .firstOrNull ??
        'Any';
    final mood =
        moods.entries
            .where((e) => lower.contains(e.key))
            .map((e) => e.value)
            .firstOrNull ??
        'Any';
    final count =
        int.tryParse(RegExp(r'\b(\d{1,3})\b').firstMatch(lower)?[1] ?? '') ??
        20;
    return MusicPrompt(
      value,
      language: language,
      mood: mood,
      limit: count.clamp(5, 50),
    );
  }
}

List<Song> rankDiscovery(
  List<Song> tracks, {
  required bool Function(Song) accepts,
  Set<String> recent = const {},
  String language = 'Any',
  Map<String, int> feedback = const {},
}) {
  final filtered = tracks.where(accepts).toList();
  filtered.sort((a, b) {
    int score(Song s) =>
        (language != 'Any' && s.language.toLowerCase() == language.toLowerCase()
            ? 10
            : 0) -
        (recent.contains(s.id) ? 3 : 0) +
        (feedback[s.id] ?? 0);
    return score(b).compareTo(score(a));
  });
  return mergeMusicResults([filtered]);
}
