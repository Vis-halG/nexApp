// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_app/app_update.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(
        utf8.encode(
          jsonEncode({
            'tag_name': 'v0.4.1+8023',
            'body': 'Playback fixes',
            'assets': [
              {
                'name': 'nexApp.apk',
                'browser_download_url': 'https://example.test/nexApp.apk',
                'size': 21000000,
              },
            ],
          }),
        ),
      ).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request extends Fake implements HttpClientRequest {
  @override
  final headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => _Response();
}

class _Client extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request();
}

void main() {
  test(
    'release response selects an APK and recognizes a newer installed build',
    () async {
      final service = AppUpdateService(_Client());
      // Simulate being on earlier version 0.2.0+4002:
      final update = await service.checkForUpdate(currentVersion: '0.2.0+4002');
      print('Update detected: ${update?.displayVersion}');
      print('Download URL: ${update?.downloadUrl}');
      print('Size: ${update?.formattedSize}');
      expect(update, isNotNull);
      expect(update!.versionName.isNotEmpty, isTrue);
      expect(update.buildNumber, greaterThan(4002));
      expect(update.downloadUrl, endsWith('.apk'));
      expect(
        await service.checkForUpdate(currentVersion: '0.4.0+8022'),
        isNotNull,
      );
      expect(
        await service.checkForUpdate(currentVersion: '0.4.1+8023'),
        isNull,
      );
    },
  );

  test('isNewerVersion logic', () {
    expect(
      AppUpdateService.isNewerVersion('0.2.9+4013', '0.2.9+4013'),
      isFalse,
    );
    expect(AppUpdateService.isNewerVersion('0.2.9+4013', '0.2.9+4011'), isTrue);
    expect(
      AppUpdateService.isNewerVersion('0.2.9+4011', '0.2.9+4013'),
      isFalse,
    );
    expect(AppUpdateService.isNewerVersion('0.3.0', '0.2.9+4013'), isTrue);
  });
}
