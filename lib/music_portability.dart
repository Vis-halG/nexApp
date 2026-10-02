import 'music_data.dart';
import 'listening_models.dart';

List<List<String>> parseMusicCsv(String input) {
  if (input.length > 1024 * 1024) {
    throw const FormatException('Choose a CSV under 1 MB.');
  }
  final rows = <List<String>>[];
  var row = <String>[], field = StringBuffer(), quoted = false;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (c == '"') {
      if (quoted && i + 1 < input.length && input[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((c == '\n' || c == '\r') && !quoted) {
      if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
      row.add(field.toString());
      if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
      row = [];
      field = StringBuffer();
    } else {
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('A CSV quote was left open.');
  row.add(field.toString());
  if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
  if (rows.length > 301) {
    throw const FormatException('Import up to 300 tracks at a time.');
  }
  return rows;
}

String exportPlaylistCsv(MusicPlaylist playlist) {
  const fields = [
    'id',
    'title',
    'artist',
    'album',
    'providerId',
    'sourceId',
    'url',
    'kind',
    'contentType',
  ];
  String cell(String value) {
    if (RegExp(r'^[=+@-]').hasMatch(value)) value = "'$value";
    return '"${value.replaceAll('"', '""')}"';
  }

  return [
    fields.map(cell).join(','),
    for (final song in playlist.tracks)
      fields
          .map((key) => cell('${trackJson(song, cloud: true)[key] ?? ''}'))
          .join(','),
  ].join('\r\n');
}

List<Map<String, String>> importPlaylistCsv(String input) {
  final rows = parseMusicCsv(input.replaceFirst('\ufeff', ''));
  if (rows.isEmpty) throw const FormatException('This CSV is empty.');
  final header = rows.first
      .map((f) => f.trim().toLowerCase().replaceAll(RegExp(r'[^a-z]'), ''))
      .toList();
  String key(String f) => switch (f) {
    'trackname' || 'songname' || 'name' => 'title',
    'artistname' || 'artists' => 'artist',
    'providerid' => 'providerId',
    'sourceid' => 'sourceId',
    'contenttype' => 'contentType',
    _ => f,
  };
  if (!header.map(key).contains('title')) {
    throw const FormatException('Include a title or Track Name column.');
  }
  return [
    for (final row in rows.skip(1))
      {
        for (var i = 0; i < header.length; i++)
          key(header[i]): i < row.length
              ? row[i].replaceFirst(RegExp(r"^'(?=[=+@-])"), '')
              : '',
      },
  ];
}

Song? csvReferencedSong(Map<String, String> row) {
  final provider = row['providerId'] ?? '',
      source = row['sourceId'] ?? '',
      url = row['url'] ?? '';
  if (!['jiosaavn', 'ytmusic', 'ytvideo'].contains(provider) &&
      !url.startsWith('https:') &&
      !url.startsWith('device:')) {
    return null;
  }
  if (provider.isNotEmpty &&
      (!['jiosaavn', 'ytmusic', 'ytvideo'].contains(provider) ||
          source.isEmpty)) {
    return null;
  }
  return Song(
    id: row['id']?.isNotEmpty == true
        ? row['id']!
        : provider.isNotEmpty
        ? 'provider:$provider:$source'
        : 'import:${musicStorageId(url)}',
    title: row['title'] ?? 'Imported track',
    artist: row['artist'] ?? '',
    album: row['album'] ?? '',
    kind: row['kind'] == 'video' ? 'video' : 'audio',
    providerId: provider,
    sourceId: source,
    url: provider.isNotEmpty ? '' : url,
    contentType: row['contentType'] ?? 'music',
  );
}
