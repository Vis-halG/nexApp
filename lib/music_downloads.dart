import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'listening_models.dart';
import 'music_data.dart';

enum MusicDownloadStatus {
  queued,
  downloading,
  paused,
  complete,
  failed,
  cancelled,
}

class MusicDownload {
  MusicDownload(this.song);
  final Song song;
  MusicDownloadStatus status = MusicDownloadStatus.queued;
  double progress = 0;
  int bytes = 0, total = 0;
  String? error;
}

class MusicDownloads extends ChangeNotifier {
  MusicDownloads({
    required this.prefs,
    required this.storageKey,
    required this.paths,
    required this.tracks,
    required this.settings,
    required this.resolve,
    required this.headers,
    required this.onSaved,
    this.onProgress,
    Future<bool> Function()? wifiCheck,
  }) : _wifiCheck = wifiCheck ?? _onWifi {
    try {
      final saved = jsonDecode(prefs.getString('$storageKey:queue') ?? '{}');
      if (saved is Map) {
        paused = saved['paused'] == true;
        for (final raw in (saved['jobs'] as List? ?? []).whereType<Map>()) {
          final song = readSongs([raw['song']]).firstOrNull;
          if (song == null) continue;
          final job = MusicDownload(song);
          job.error = raw['error'] as String?;
          job.status = raw['status'] == 'failed'
              ? MusicDownloadStatus.failed
              : MusicDownloadStatus.queued;
          jobs[song.id] = job;
        }
      }
    } catch (_) {}
    if (jobs.isNotEmpty && !paused) {
      scheduleMicrotask(() => unawaited(_drain()));
    }
    if (!kIsWeb) {
      _network = Connectivity().onConnectivityChanged.listen((_) {
        if (!paused) unawaited(resume());
      }, onError: (Object _) {});
    }
  }
  final SharedPreferences prefs;
  final String storageKey;
  final Map<String, String> paths;
  final Map<String, Song> tracks;
  final ListeningSettings Function() settings;
  final Future<String> Function(Song song) resolve;
  final Map<String, String> Function(Song song) headers;
  final void Function() onSaved;
  final void Function(MusicDownload job)? onProgress;
  final Future<bool> Function() _wifiCheck;
  final Map<String, MusicDownload> jobs = {};
  final Map<String, HttpClient> _clients = {};
  StreamSubscription<dynamic>? _network;
  bool _running = false, _disposed = false, paused = false;
  bool _drainAgain = false;
  int bytesOnDisk = 0;
  static Future<bool> _onWifi() async {
    final status = await Connectivity().checkConnectivity();
    return status.contains(ConnectivityResult.wifi) ||
        status.contains(ConnectivityResult.ethernet);
  }

  Future<void> enqueue(Iterable<Song> songs) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Offline downloads are available in the installed app.',
      );
    }
    for (final song in songs) {
      if (song.isLocal ||
          song.url.startsWith('device:') ||
          (paths[song.id] != null && File(paths[song.id]!).existsSync())) {
        continue;
      }
      final existing = jobs[song.id];
      if (existing != null &&
          {
            MusicDownloadStatus.queued,
            MusicDownloadStatus.downloading,
          }.contains(existing.status)) {
        continue;
      }
      jobs[song.id] = MusicDownload(song);
    }
    _emit();
    unawaited(_drain());
  }

  void _emit() {
    if (!_disposed) {
      final data = jsonEncode({
        'paused': paused,
        'jobs': [
          for (final job in jobs.values.where(
            (j) => !{
              MusicDownloadStatus.complete,
              MusicDownloadStatus.cancelled,
            }.contains(j.status),
          ))
            {
              'song': trackJson(job.song),
              'status': job.status.name,
              'error': job.error,
            },
        ],
      });
      if (_savedQueue != data) {
        _savedQueue = data;
        unawaited(prefs.setString('$storageKey:queue', data));
      }
      notifyListeners();
    }
  }

  String? _savedQueue;

  Future<void> _drain() async {
    if (_disposed || paused) return;
    if (_running) {
      _drainAgain = true;
      return;
    }
    _running = true;
    try {
      while (!_disposed && !paused) {
        final job = jobs.values
            .where((j) => j.status == MusicDownloadStatus.queued)
            .firstOrNull;
        if (job == null) break;
        if (settings().wifiOnly && !await _wifiCheck()) {
          job.status = MusicDownloadStatus.paused;
          job.error = 'Waiting for Wi-Fi';
          _emit();
          break;
        }
        await _download(job);
      }
    } finally {
      _running = false;
      if (_drainAgain && !_disposed && !paused) {
        _drainAgain = false;
        scheduleMicrotask(() => unawaited(_drain()));
      }
    }
  }

  Future<void> _download(MusicDownload job) async {
    File? partial;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _clients[job.song.id] = client;
    job.status = MusicDownloadStatus.downloading;
    job.error = null;
    job.bytes = 0;
    job.progress = 0;
    _emit();
    try {
      final url = await resolve(job.song);
      if (_disposed || job.status != MusicDownloadStatus.downloading) return;
      final uri = Uri.parse(url);
      if (uri.scheme != 'https') {
        throw const FormatException('This source cannot be downloaded.');
      }
      final docs = await getApplicationDocumentsDirectory();
      final scope = base64Url
          .encode(utf8.encode(storageKey))
          .replaceAll('=', '');
      final directory = Directory(path.join(docs.path, 'offline_songs', scope));
      await directory.create(recursive: true);
      final id = musicStorageId(job.song.id);
      final ext = job.song.providerId.startsWith('yt')
          ? '.mp4'
          : path.extension(uri.path);
      final file = File(
        path.join(
          directory.path,
          '$id${ext.isEmpty || ext.length > 8 ? '.mp3' : ext}',
        ),
      );
      partial = File('${file.path}.part');
      final request = await client.getUrl(uri);
      headers(job.song).forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      job.total = response.contentLength;
      await measureStorage();
      final budget = settings().storageBudgetMb * 1024 * 1024;
      if (job.total > 0 && bytesOnDisk + job.total > budget) {
        throw const FileSystemException(
          'Download storage limit reached. Remove downloads or increase the limit.',
        );
      }
      final sink = partial.openWrite();
      var lastNotify = DateTime.now();
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          if (_disposed || job.status != MusicDownloadStatus.downloading) {
            throw const HttpException('Download stopped');
          }
          job.bytes += chunk.length;
          if (bytesOnDisk + job.bytes > budget) {
            throw const FileSystemException('Download storage limit reached.');
          }
          sink.add(chunk);
          job.progress = job.total > 0
              ? (job.bytes / job.total).clamp(0, 1)
              : 0;
          if (DateTime.now().difference(lastNotify).inMilliseconds > 300) {
            lastNotify = DateTime.now();
            onProgress?.call(job);
            _emit();
          }
        }
      } finally {
        await sink.close();
      }
      if (job.bytes == 0 || (job.total > 0 && job.bytes != job.total)) {
        throw const FileSystemException(
          'The download was incomplete. Retry it.',
        );
      }
      if (_disposed || job.status != MusicDownloadStatus.downloading) return;
      await partial.rename(file.path);
      partial = null;
      paths[job.song.id] = file.path;
      tracks[job.song.id] = job.song;
      await prefs.setString(storageKey, jsonEncode(paths));
      bytesOnDisk += job.bytes;
      job.status = MusicDownloadStatus.complete;
      job.progress = 1;
      onSaved();
      onProgress?.call(job);
    } catch (e) {
      if (job.status == MusicDownloadStatus.downloading) {
        job.status = MusicDownloadStatus.failed;
        job.error = '$e';
      }
    } finally {
      client.close(force: true);
      _clients.remove(job.song.id);
      if (partial != null && await partial.exists()) await partial.delete();
      _emit();
    }
  }

  void cancel(String id) {
    final job = jobs[id];
    if (job == null) return;
    job.status = MusicDownloadStatus.cancelled;
    _clients[id]?.close(force: true);
    _emit();
  }

  void pause() {
    paused = true;
    for (final job in jobs.values) {
      if (job.status == MusicDownloadStatus.downloading) {
        job.status = MusicDownloadStatus.paused;
        _clients[job.song.id]?.close(force: true);
      }
    }
    _emit();
  }

  Future<void> resume() async {
    if (_disposed) return;
    if (settings().wifiOnly && !await _wifiCheck()) return;
    paused = false;
    for (final job in jobs.values) {
      if (job.status == MusicDownloadStatus.paused) {
        job.status = MusicDownloadStatus.queued;
        job.bytes = 0;
        job.progress = 0;
        job.error = null;
      }
    }
    _emit();
    await _drain();
  }

  Future<void> retry(String id) async {
    final job = jobs[id];
    if (job == null) return;
    job.status = MusicDownloadStatus.queued;
    job.bytes = 0;
    job.progress = 0;
    job.error = null;
    _emit();
    await _drain();
  }

  Future<void> remove(String id) async {
    cancel(id);
    final location = paths.remove(id);
    tracks.remove(id);
    if (location != null) {
      final file = File(location);
      if (await file.exists()) await file.delete();
    }
    await prefs.setString(storageKey, jsonEncode(paths));
    onSaved();
    await measureStorage();
    _emit();
  }

  Future<void> measureStorage() async {
    var total = 0;
    for (final location in paths.values.toList()) {
      try {
        total += await File(location).length();
      } catch (_) {}
    }
    bytesOnDisk = total;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_network?.cancel());
    for (final client in _clients.values) {
      client.close(force: true);
    }
    super.dispose();
  }
}
