import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_music/music_artists.dart';
import 'package:nex_music/music_controller.dart';
import 'package:nex_music/music_data.dart';
import 'package:nex_music/music_ui.dart';
import 'package:nex_music/personal_music.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song track(String id, String artist) => Song(
  id: id,
  title: 'Song $id',
  kind: 'audio',
  url: 'https://test.example/$id.mp3',
  artist: artist,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'artist grouping normalizes credits, deduplicates songs, and keeps missing tags honest',
    () {
      final a = track('a', '  Arijit   Singh, Shreya Ghoshal; arijit singh');
      final groups = groupSongsByArtist([
        a,
        a.copyWith(artist: ''),
        track('b', 'arijit singh'),
        track('c', '<unknown>').copyWith(ownerName: 'Uploader'),
        track('d', 'Singer').copyWith(kind: 'video'),
        track('e', 'Host').copyWith(contentType: 'podcast'),
        track('f', '歌手'),
      ]);
      expect(groups.map((g) => g.name), [
        'Arijit Singh',
        'Shreya Ghoshal',
        '歌手',
        'Unknown artist',
      ]);
      expect(groups.first.tracks.map((s) => s.id), ['a', 'b']);
      expect(groups[1].tracks.single.id, 'a');
      expect(groups.last.tracks.single.id, 'c');
      expect(songArtistNames(track('band', 'AC/DC')), ['AC/DC']);
    },
  );

  test(
    'manual artist tags survive restart and stay within their account',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final music = MusicController(prefs)..songs = [track('a', '')];
      music.setSongArtist(music.songs.single, 'New Artist');
      await music.personal.saved;
      music.dispose();
      final restored = MusicController(prefs)..songs = [track('a', '')];
      expect(restored.artistCategories.single.name, 'New Artist');
      restored.dispose();
      final alice = PersonalMusic(prefs, uid: 'alice');
      alice.songArtists['a'] = 'Alice Artist';
      alice.changed(sync: false);
      await alice.saved;
      final bob = PersonalMusic(prefs, uid: 'bob');
      expect(bob.songArtists, isEmpty);
      final aliceAgain = PersonalMusic(prefs, uid: 'alice');
      expect(aliceAgain.songArtists['a'], 'Alice Artist');
      alice.dispose();
      bob.dispose();
      aliceAgain.dispose();
    },
  );

  testWidgets('artist search opens only the selected artists songs', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final music = MusicController(await SharedPreferences.getInstance())
      ..songs = [
        track('a', 'Arijit Singh, Shreya Ghoshal'),
        track('b', 'Arijit Singh'),
        track('c', 'Other Singer'),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: music,
        child: const MaterialApp(home: MusicArtistsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Arijit Singh'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'shreya');
    await tester.pumpAndSettle();
    expect(find.text('Other Singer'), findsNothing);
    await tester.tap(find.text('Shreya Ghoshal'));
    await tester.pumpAndSettle();
    expect(find.text('Song a'), findsOneWidget);
    expect(find.text('Song b'), findsNothing);
    expect(find.text('Song c'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    music.dispose();
  });
}
