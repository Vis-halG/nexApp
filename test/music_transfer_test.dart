import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_app/listening_models.dart';
import 'package:nex_app/music_controller.dart';
import 'package:nex_app/music_data.dart';
import 'package:nex_app/music_downloads.dart';
import 'package:nex_app/music_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song _song(String id, {String provider = ''}) => Song(
  id: id,
  title: id,
  kind: 'audio',
  url: 'https://music.test/$id.mp3',
  providerId: provider,
  sourceId: id,
);

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), true, reason: 'Transfer did not reach the expected state');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late Directory directory;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    directory = await Directory.systemTemp.createTemp('nex-transfer-');
  });
  tearDown(() async => directory.delete(recursive: true));

  MusicDownloads downloads({
    required HttpClient Function() client,
    Future<String> Function(Song)? resolve,
    ListeningSettings Function()? settings,
    Future<bool> Function()? wifi,
    Stream<List<ConnectivityResult>> network = const Stream.empty(),
    Duration retryDelay = const Duration(hours: 1),
  }) {
    final manager = MusicDownloads(
      prefs: prefs,
      storageKey: 'transfer',
      paths: {},
      tracks: {},
      settings: settings ?? () => ListeningSettings({'wifiOnly': false}),
      resolve: resolve ?? (song) async => song.url,
      headers: (_) => {},
      onSaved: () {},
      wifiCheck: wifi ?? () async => true,
      clientFactory: client,
      documentsDirectory: () async => directory,
      networkChanges: network,
      retryDelay: retryDelay,
    );
    addTearDown(manager.dispose);
    return manager;
  }

  test(
    'DNS outage retains the whole download queue and reconnect resumes it',
    () async {
      var online = false, attempts = 0;
      final network = StreamController<List<ConnectivityResult>>();
      addTearDown(network.close);
      final manager = downloads(
        network: network.stream,
        client: () => _Client(
          getCallback: (uri) async {
            attempts++;
            if (!online) throw const SocketException('Failed host lookup');
            return _Request(() async => _Response.bytes([1, 2, 3]));
          },
        ),
      );
      await manager.enqueue([_song('a'), _song('b')]);
      await _until(() => manager.waitingMessage != null);
      expect(attempts, 1);
      expect(
        manager.jobs.values.every(
          (j) => j.status == MusicDownloadStatus.paused,
        ),
        true,
      );
      expect(manager.paths, isEmpty);
      online = true;
      network.add([ConnectivityResult.wifi]);
      await _until(() => manager.paths.length == 2);
      expect(attempts, 3);
      expect(await File(manager.paths['a']!).readAsBytes(), [1, 2, 3]);
      expect(manager.waitingMessage, isNull);
    },
  );

  test(
    'interrupted stream discards partial bytes before automatic retry',
    () async {
      var attempts = 0;
      Stream<List<int>> interrupted() async* {
        yield [9, 9];
        throw const SocketException('Connection reset');
      }

      final manager = downloads(
        retryDelay: const Duration(milliseconds: 30),
        client: () => _Client(
          getCallback: (_) async => _Request(() async {
            attempts++;
            return attempts == 1
                ? _Response(interrupted(), length: 4)
                : _Response.bytes([1, 2, 3, 4]);
          }),
        ),
      );
      await manager.enqueue([_song('a')]);
      await _until(
        () => manager.jobs['a']!.status == MusicDownloadStatus.complete,
      );
      expect(attempts, 2);
      expect(await File(manager.paths['a']!).readAsBytes(), [1, 2, 3, 4]);
      expect(manager.bytesOnDisk, 4);
      expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.part')),
        isEmpty,
      );
    },
  );

  test(
    'expired provider link refreshes once; permanent refusal does not loop',
    () async {
      var resolutions = 0, responses = 0;
      final manager = downloads(
        resolve: (_) async => 'https://music.test/${++resolutions}.mp4',
        client: () => _Client(
          getCallback: (_) async => _Request(() async {
            responses++;
            return _Response.bytes([1, 2], status: responses == 1 ? 403 : 200);
          }),
        ),
      );
      await manager.enqueue([_song('a', provider: 'ytmusic')]);
      await _until(() => manager.paths.isNotEmpty);
      expect(resolutions, 2);
      final refused = downloads(
        client: () => _Client(
          getCallback: (_) async =>
              _Request(() async => _Response.bytes([], status: 403)),
        ),
      );
      await refused.enqueue([_song('b', provider: 'ytmusic')]);
      await _until(
        () => refused.jobs['b']!.status == MusicDownloadStatus.failed,
      );
      expect(refused.waitingMessage, isNull);
      expect(refused.paths, isEmpty);
    },
  );

  test(
    'Wi-Fi wait covers every queued song and mobile-data opt-in resumes',
    () async {
      final settings = ListeningSettings();
      var attempts = 0;
      final manager = downloads(
        settings: () => settings,
        wifi: () async => false,
        client: () => _Client(
          getCallback: (_) async {
            attempts++;
            return _Request(() async => _Response.bytes([1]));
          },
        ),
      );
      await manager.enqueue([_song('a'), _song('b')]);
      expect(manager.waitingForWifi, true);
      expect(
        manager.jobs.values.every(
          (j) => j.status == MusicDownloadStatus.paused,
        ),
        true,
      );
      expect(attempts, 0);
      manager.pause();
      await manager.resume();
      expect(manager.paused, false);
      expect(manager.waitingForWifi, true);
      settings.values['wifiOnly'] = false;
      await manager.resume();
      expect(manager.paths.length, 2);
    },
  );

  test(
    'missing source fails only that song and does not block other downloads',
    () async {
      final manager = downloads(
        client: () => _Client(
          getCallback: (uri) async => _Request(
            () async => _Response.bytes([
              1,
            ], status: uri.path.contains('/a.') ? 404 : 200),
          ),
        ),
      );
      await manager.enqueue([_song('a'), _song('b')]);
      await _until(() => manager.paths.containsKey('b'));
      expect(manager.jobs['a']!.status, MusicDownloadStatus.failed);
      expect(manager.paths.containsKey('a'), false);
      expect(manager.waitingMessage, isNull);
    },
  );

  test(
    'manual pause suppresses reconnect and timer retries until explicit resume',
    () async {
      var attempts = 0, online = false;
      final network = StreamController<List<ConnectivityResult>>();
      addTearDown(network.close);
      final manager = downloads(
        retryDelay: const Duration(milliseconds: 25),
        network: network.stream,
        client: () => _Client(
          getCallback: (_) async {
            attempts++;
            if (!online) throw const SocketException('offline');
            return _Request(() async => _Response.bytes([1]));
          },
        ),
      );
      await manager.enqueue([_song('a')]);
      await _until(() => manager.waitingMessage != null);
      manager.pause();
      online = true;
      network.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(attempts, 1);
      expect(manager.paused, true);
      await manager.resume();
      expect(manager.paths.length, 1);
    },
  );

  test(
    'downloads resolve a fresh provider URL instead of a transient song URL',
    () async {
      final provider = _Provider();
      final music = MusicController(prefs, musicProvider: provider);
      addTearDown(music.dispose);
      final song = _song('a', provider: provider.id);
      expect(await music.resolvedPlayableUrl(song), song.url);
      expect(provider.calls, 0);
      expect(
        await music.resolvedPlayableUrl(song, downloading: true),
        'https://fresh.test/song.mp3',
      );
      expect(provider.calls, 1);
      expect(provider.last!.url, isEmpty);
    },
  );

  Future<(MusicController, List<UploadItem>)> uploader(
    _Firestore firestore, {
    int count = 1,
  }) async {
    final file = await File(
      '${directory.path}/upload.mp3',
    ).writeAsBytes([1, 2, 3]);
    final music = MusicController(prefs, auth: _Auth(), firestore: firestore);
    music.categories = const [
      MusicCategory(id: 'c', name: 'Category', ownerUid: 'guest'),
    ];
    addTearDown(music.dispose);
    final items = List.generate(
      count,
      (i) => UploadItem(
        path: file.path,
        name: 'upload.mp3',
        sizeBytes: 3,
        title: 'Song $i',
      ),
    );
    return (music, items);
  }

  _Request uploadReply(int index) => _Request(
    () async => _Response.bytes(
      utf8.encode(
        jsonEncode({
          'secure_url':
              'https://res.cloudinary.com/test/video/upload/$index.mp3',
          'public_id': 'song$index',
          'duration': 12,
        }),
      ),
      type: ContentType.json,
    ),
  );

  test(
    'Cloudinary DNS failure stops a large batch and resumes without mass failures',
    () async {
      await HttpOverrides.runZoned(() async {
        final firestore = _Firestore();
        final (music, items) = await uploader(firestore, count: 100);
        var online = false, attempts = 0;
        _post = (_) async {
          attempts++;
          if (!online) {
            throw const SocketException(
              'Failed host lookup: api.cloudinary.com',
            );
          }
          return uploadReply(attempts);
        };
        await music.startUploads(items, categoryId: 'c');
        expect(music.uploadsWaiting, true);
        expect(music.uploadsFailed, 0);
        expect(attempts, lessThanOrEqualTo(3));
        expect(
          music.uploads.every((i) => i.status == UploadStatus.queued),
          true,
        );
        music.pauseUploads();
        online = true;
        expect(music.uploadsPaused, true);
        await music.resumeUploads();
        expect(music.uploadsFinished, 100);
        expect(music.uploadsFailed, 0);
        expect(firestore.records.length, 100);
        expect(music.songs.first.durationMs, 12000);
      }, createHttpClient: (_) => _Client(postCallback: (uri) => _post(uri)));
    },
  );

  test(
    'catalogue outage retries the same document without reuploading its file',
    () async {
      await HttpOverrides.runZoned(() async {
        final firestore = _Firestore()..failNextWrite = true;
        final (music, items) = await uploader(firestore);
        items.single.artist = 'Tagged Artist';
        var requests = 0;
        _post = (_) async => uploadReply(++requests);
        await music.startUploads(items, categoryId: 'c');
        expect(music.uploadsWaiting, true);
        final id = music.uploads.single.catalogId;
        expect(id, isNotNull);
        expect(music.uploads.single.uploadedUrl, isNotNull);
        await music.resumeUploads();
        expect(requests, 1);
        expect(firestore.records.keys, [id]);
        expect(music.uploads.single.status, UploadStatus.done);
        expect(music.personal.songArtists[id], 'Tagged Artist');
        expect(firestore.records[id]!.containsKey('artist'), false);
      }, createHttpClient: (_) => _Client(postCallback: (uri) => _post(uri)));
    },
  );

  test(
    'retry after a lost catalogue acknowledgement reads the original document without overwriting it',
    () async {
      await HttpOverrides.runZoned(() async {
        final firestore = _Firestore()..loseCommitReply = true;
        final (music, items) = await uploader(firestore);
        var uploads = 0;
        _post = (_) async => uploadReply(++uploads);
        await music.startUploads(items, categoryId: 'c');
        expect(music.uploadsWaiting, true);
        expect(firestore.records.length, 1);
        await music.resumeUploads();
        expect(uploads, 1);
        expect(firestore.writes, 1);
        expect(music.uploads.single.status, UploadStatus.done);
      }, createHttpClient: (_) => _Client(postCallback: (uri) => _post(uri)));
    },
  );

  test(
    'gateway HTML outage is retryable, while invalid upload preset fails',
    () async {
      await HttpOverrides.runZoned(() async {
        final (music, items) = await uploader(_Firestore());
        _post = (_) async => _Request(
          () async => _Response.bytes(
            utf8.encode('<html>Unavailable</html>'),
            status: 503,
          ),
        );
        await music.startUploads(items, categoryId: 'c');
        expect(music.uploadsWaiting, true);
        _post = (_) async => _Request(
          () async => _Response.bytes(
            utf8.encode('{"error":{"message":"Unknown preset"}}'),
            status: 400,
          ),
        );
        await music.resumeUploads();
        expect(music.uploadsWaiting, false);
        expect(music.uploadsFailed, 1);
        expect(music.uploads.single.error, contains('Unknown preset'));
      }, createHttpClient: (_) => _Client(postCallback: (uri) => _post(uri)));
    },
  );
}

late Future<HttpClientRequest> Function(Uri) _post;

class _Client extends Fake implements HttpClient {
  _Client({this.getCallback, this.postCallback});
  final Future<HttpClientRequest> Function(Uri)? getCallback, postCallback;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) => getCallback!(uri);
  @override
  Future<HttpClientRequest> postUrl(Uri uri) => postCallback!(uri);
  @override
  void close({bool force = false}) {}
}

class _Headers extends Fake implements HttpHeaders {
  _Headers({this.contentType});
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.reply);
  final Future<HttpClientResponse> Function() reply;
  @override
  final HttpHeaders headers = _Headers();
  @override
  int contentLength = 0;
  @override
  void add(List<int> data) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) async =>
      stream.drain<void>();
  @override
  Future<HttpClientResponse> close() => reply();
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.body, {int length = 0, int status = 200, ContentType? type})
    : contentLength = length,
      statusCode = status,
      headers = _Headers(contentType: type);
  factory _Response.bytes(
    List<int> bytes, {
    int status = 200,
    ContentType? type,
  }) => _Response(
    Stream.value(bytes),
    length: bytes.length,
    status: status,
    type: type,
  );
  final Stream<List<int>> body;
  @override
  final int statusCode, contentLength;
  @override
  final HttpHeaders headers;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Provider extends Fake implements MusicProvider {
  int calls = 0;
  Song? last;
  @override
  String get id => 'test';
  @override
  Future<String> resolveStreamUrl(Song song) async {
    calls++;
    last = song;
    return 'https://fresh.test/song.mp3';
  }
}

class _Auth extends Fake implements FirebaseAuth {
  @override
  User get currentUser => _User();
  @override
  Stream<User?> authStateChanges() => const Stream.empty();
}

class _User extends Fake implements User {
  @override
  String get uid => 'guest';
  @override
  String get displayName => 'Test';
  @override
  String get email => 'test@example.com';
}

class _Firestore extends Fake implements FirebaseFirestore {
  final records = <String, Map<String, dynamic>>{};
  bool failNextWrite = false;
  bool loseCommitReply = false;
  int writes = 0;
  int nextId = 0;
  @override
  CollectionReference<Map<String, dynamic>> collection(String name) =>
      _Collection(this);
  @override
  Future<T> runTransaction<T>(
    Future<T> Function(Transaction) handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    final transaction = _Transaction(this);
    final result = await handler(transaction);
    for (final entry in transaction.pending.entries) {
      writes++;
      records[entry.key] = {
        ...entry.value,
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
      };
    }
    if (loseCommitReply) {
      loseCommitReply = false;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return result;
  }
}

class _Transaction extends Fake implements Transaction {
  _Transaction(this.store);
  final _Firestore store;
  final pending = <String, Map<String, dynamic>>{};
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> reference,
  ) async => _Snapshot<T>(store.records[reference.id] as T?);
  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    pending[reference.id] = Map<String, dynamic>.from(data as Map);
    return this;
  }
}

// ignore: subtype_of_sealed_class
class _Snapshot<T> extends Fake implements DocumentSnapshot<T> {
  _Snapshot(this.value);
  final T? value;
  @override
  T? data() => value;
}

// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.store);
  final _Firestore store;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(store, path ?? 'id${store.nextId++}');
}

// ignore: subtype_of_sealed_class
class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Document(this.store, this.id);
  final _Firestore store;
  @override
  final String id;
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    if (store.failNextWrite) {
      store.failNextWrite = false;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    store.records[id] = data;
  }
}
