import 'dart:convert';

import 'package:airport_mobile/core/github_updates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object> release(String tag, {String? url}) => {
  'tag_name': tag, 'draft': false, 'prerelease': false,
  'assets': [{'browser_download_url': url ??
    'https://github.com/clashnova-dev/ClashNova-Mobile/releases/download/$tag/app.apk'}],
};

void main() {
  test('versions use numeric ordering and reject invalid tags', () {
    expect(isNewerVersion('v0.10.0', '0.9.9'), isTrue);
    expect(isNewerVersion('0.1.0', '0.1.0'), isFalse);
    expect(isNewerVersion('0.0.9', '0.1.0'), isFalse);
    expect(() => isNewerVersion('latest', '0.1.0'), throwsFormatException);
  });

  test('updates come from the project GitHub release with an Android APK', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(),
        'https://api.github.com/repos/clashnova-dev/ClashNova-Mobile/releases/latest');
      return http.Response(jsonEncode(release('v0.2.0')), 200);
    });
    final update = await checkGitHubUpdate(currentVersion: '0.1.0', client: client);
    expect(update?.version, '0.2.0');
    expect(update?.releaseUrl.toString(),
      'https://github.com/clashnova-dev/ClashNova-Mobile/releases/tag/v0.2.0');
  });

  test('no release and the current release do not offer an update', () async {
    for (final response in [
      http.Response('', 404),
      http.Response(jsonEncode(release('v0.1.0')), 200),
    ]) {
      expect(await checkGitHubUpdate(currentVersion: '0.1.0',
        client: MockClient((_) async => response)), isNull);
    }
  });

  test('API failures and external APK downloads are rejected', () async {
    for (final response in [
      http.Response('', 403),
      http.Response(jsonEncode(release('v0.2.0', url: 'https://example.com/app.apk')), 200),
      http.Response(jsonEncode({...release('v0.2.0'), 'prerelease': true}), 200),
      http.Response('[]', 200),
    ]) {
      await expectLater(checkGitHubUpdate(currentVersion: '0.1.0',
        client: MockClient((_) async => response)), throwsFormatException);
    }
  });
}
