import 'package:flutter_test/flutter_test.dart';
import 'package:nex_app/app_update.dart';

void main() {
  test('live GitHub release endpoint', () async {
    final update = await AppUpdateService().checkForUpdate(
      currentVersion: '0.2.0+4002',
    );
    expect(update, isNotNull);
    expect(update!.downloadUrl, endsWith('.apk'));
  }, timeout: const Timeout(Duration(seconds: 50)));
}
