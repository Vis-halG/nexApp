import 'music_data.dart';

class MusicArtistCategory {
  MusicArtistCategory(this.name, this.tracks);
  final String name;
  final List<Song> tracks;
  String get key => name.toLowerCase();
  bool get unknown => name == 'Unknown artist';
}

List<String> songArtistNames(Song song) {
  return song.artist
      .split(
        RegExp(r'[,;]|\s+(?:feat\.?|ft\.?|featuring)\s+', caseSensitive: false),
      )
      .map((a) => a.trim().replaceAll(RegExp(r'\s+'), ' '))
      .where(
        (a) =>
            a.isNotEmpty &&
            !{
              '<unknown>',
              'unknown',
              'unknown artist',
            }.contains(a.toLowerCase()),
      )
      .toList();
}

/// Collaborations appear under each credited artist. Unknown tags stay honest;
/// uploader names and filenames are never used to guess a performer.
List<MusicArtistCategory> groupSongsByArtist(Iterable<Song> songs) {
  final groups = <String, MusicArtistCategory>{};
  final seen = <String>{};
  for (final song in songs) {
    if (song.isVideo || song.isLongform || !seen.add(song.id)) continue;
    final names = songArtistNames(song);
    final credited = <String>{};
    for (final name in names.isEmpty ? ['Unknown artist'] : names) {
      final key = name.toLowerCase();
      if (!credited.add(key)) continue;
      groups
          .putIfAbsent(key, () => MusicArtistCategory(name, []))
          .tracks
          .add(song);
    }
  }
  final categories = groups.values.toList();
  for (final category in categories) {
    category.tracks.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
  }
  categories.sort(
    (a, b) => a.unknown == b.unknown
        ? a.key.compareTo(b.key)
        : a.unknown
        ? 1
        : -1,
  );
  return categories;
}
