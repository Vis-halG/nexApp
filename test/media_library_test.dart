import 'package:flutter_test/flutter_test.dart';
import 'package:nex_music/media_library.dart';
import 'package:nex_music/music_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song _song(String id, {String provider = 'jiosaavn', String kind = 'audio'}) =>
    Song(
      id: id,
      title: 'Track $id',
      kind: kind,
      url: 'https://example.com/$id',
      providerId: provider,
    );

void main() {
  test('home collections mix sources and survive a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final saavn = _song('s1');
    final yt = _song('y1', provider: 'ytmusic');
    final video = _song('v1', provider: 'ytvideo', kind: 'video');
    final unplayed = _song('u1');
    final library = MediaLibrary(prefs)
      ..rememberSongs([saavn, yt, video, unplayed])
      ..recordSongPlay(saavn)
      ..recordSongPlay(yt)
      ..recordSongPlay(yt)
      ..recordSongPlay(video)
      ..setSongLiked(saavn, true);
    await library.saved;

    List<String> ids(MediaLibrary l, MediaCollection c) =>
        l.collection(c).map((e) => e.song.id).toList();

    expect(ids(library, MediaCollection.mostPlayed).first, 'y1');
    expect(ids(library, MediaCollection.watched), ['v1']);
    expect(ids(library, MediaCollection.likedSongs), ['s1']);
    expect(ids(library, MediaCollection.neverPlayed), ['u1']);

    final restored = MediaLibrary(prefs);
    expect(ids(restored, MediaCollection.recent).toSet(), {'s1', 'y1', 'v1'});
    expect(ids(restored, MediaCollection.likedSongs), ['s1']);
  });
}
