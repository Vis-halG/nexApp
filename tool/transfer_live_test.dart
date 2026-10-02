// Explicit network check: flutter test tool/transfer_live_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_music/listening_models.dart';
import 'package:nex_music/music_data.dart';
import 'package:nex_music/music_downloads.dart';
import 'package:nex_music/music_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This opt-in suite verifies real transfers, outside widget HTTP fixtures.
  HttpOverrides.global = null;
  test(
    'full offline downloads from JioSaavn, YouTube Music and Cloudinary',
    () async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final directory = await Directory.systemTemp.createTemp(
        'nex-live-download-',
      );
      final jio = JioSaavnProvider()..quality = 96;
      final yt = YouTubeMusicProvider()..preferLowBitrate = true;
      final providers = {jio.id: jio, yt.id: yt};
      final seeds = <Song>[
        (await jio.searchSongs('Arijit Singh', limit: 1)).first,
        (await yt.searchSongs('Arijit Singh', limit: 1)).first,
        const Song(
          id: 'cloudinary-sample',
          title: 'Cloudinary sample',
          kind: 'video',
          url: 'https://res.cloudinary.com/demo/video/upload/dog.mp4',
        ),
      ];
      final manager = MusicDownloads(
        prefs: prefs,
        storageKey: 'live-transfer',
        paths: {},
        tracks: {},
        settings: () => ListeningSettings({'wifiOnly': false}),
        resolve: (song) async => song.isProvider
            ? providers[song.providerId]!.resolveStreamUrl(song)
            : song.url,
        headers: (song) =>
            providers[song.providerId]?.playbackHeaders(song) ?? {},
        onSaved: () {},
        documentsDirectory: () async => directory,
        networkChanges: const Stream.empty(),
      );
      try {
        final complete = Completer<void>();
        manager.addListener(() {
          final done =
              manager.jobs.length == seeds.length &&
              manager.jobs.values.every(
                (j) => {
                  MusicDownloadStatus.complete,
                  MusicDownloadStatus.failed,
                }.contains(j.status),
              );
          if (done && !complete.isCompleted) complete.complete();
        });
        await manager.enqueue(seeds);
        await complete.future.timeout(const Duration(minutes: 3));
        for (final song in seeds) {
          final job = manager.jobs[song.id]!;
          expect(
            job.status,
            MusicDownloadStatus.complete,
            reason:
                '${song.providerId.isEmpty ? 'Cloudinary' : song.providerId}: ${job.error}',
          );
          final file = File(manager.paths[song.id]!);
          expect(await file.length(), greaterThan(1024));
          expect(await file.length(), job.bytes);
          expect(job.total <= 0 || job.bytes == job.total, true);
        }
        expect(
          directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.part')),
          isEmpty,
        );
      } finally {
        manager.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
