import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/update/data/github_release_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const checksum =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  test('读取最新 Release、优先 Android APK 并获取 SHA-256', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/releases/latest')) {
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.3.0',
            'name': 'Hormone v1.3.0',
            'body': '新增应用内更新',
            'html_url':
                'https://github.com/Aetik-yue/hormone/releases/tag/v1.3.0',
            'published_at': '2026-09-04T10:00:00Z',
            'assets': [
              {
                'name': 'fallback.apk',
                'browser_download_url':
                    'https://github.com/Aetik-yue/hormone/releases/download/v1.3.0/fallback.apk',
                'size': 10,
              },
              {
                'name': 'hormone-v1.3.0-android.apk',
                'browser_download_url':
                    'https://github.com/Aetik-yue/hormone/releases/download/v1.3.0/hormone-v1.3.0-android.apk',
                'size': 42 * 1024 * 1024,
              },
              {
                'name': 'hormone-v1.3.0-android.apk.sha256',
                'browser_download_url':
                    'https://github.com/Aetik-yue/hormone/releases/download/v1.3.0/hormone-v1.3.0-android.apk.sha256',
                'size': 100,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.path.endsWith('.sha256')) {
        return http.Response('$checksum  hormone-v1.3.0-android.apk\n', 200);
      }
      return http.Response('not found', 404);
    });
    final repository = GitHubReleaseRepository(client: client);

    final release = await repository.fetchLatestRelease();

    expect(release.tagName, 'v1.3.0');
    expect(release.version.toString(), '1.3.0');
    expect(release.apkFileName, 'hormone-v1.3.0-android.apk');
    expect(release.apkSize, 42 * 1024 * 1024);
    expect(release.sha256, checksum);
    expect(release.notes, '新增应用内更新');
    repository.close();
  });

  test('Release 缺少校验文件时拒绝更新', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'tag_name': 'v1.3.0',
          'name': 'Hormone v1.3.0',
          'body': '',
          'html_url':
              'https://github.com/Aetik-yue/hormone/releases/tag/v1.3.0',
          'assets': [
            {
              'name': 'hormone-v1.3.0-android.apk',
              'browser_download_url':
                  'https://github.com/Aetik-yue/hormone/releases/download/v1.3.0/hormone-v1.3.0-android.apk',
              'size': 42,
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final repository = GitHubReleaseRepository(client: client);

    await expectLater(
      repository.fetchLatestRelease(),
      throwsA(
        isA<UpdateCheckException>().having(
          (error) => error.message,
          'message',
          contains('SHA-256'),
        ),
      ),
    );
    repository.close();
  });

  for (final entry
      in {
        '仅含哈希的独立校验文件': checksum,
        '错误 APK 文件名的校验条目': '$checksum  other.apk\n',
      }.entries) {
    test(entry.key, () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'tag_name': 'v1.3.0',
              'html_url':
                  'https://github.com/Aetik-yue/hormone/releases/tag/v1.3.0',
              'assets': [
                {
                  'name': 'app.apk',
                  'browser_download_url':
                      'https://github.com/Aetik-yue/hormone/app.apk',
                },
                {
                  'name': 'app.apk.sha256',
                  'browser_download_url':
                      'https://github.com/Aetik-yue/hormone/app.apk.sha256',
                },
              ],
            }),
            200,
          );
        }
        return http.Response(entry.value, 200);
      });
      final repository = GitHubReleaseRepository(client: client);
      addTearDown(repository.close);

      if (entry.value == checksum) {
        expect((await repository.fetchLatestRelease()).sha256, checksum);
      } else {
        await expectLater(
          repository.fetchLatestRelease(),
          throwsA(isA<UpdateCheckException>()),
        );
      }
    });
  }
}
