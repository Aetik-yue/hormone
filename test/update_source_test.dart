import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/update/data/github_release_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Map<String, dynamic> _manifest(List<String> abis) => {
  'tag_name': 'v1.3.0',
  'html_url': 'https://github.com/Aetik-yue/hormone/releases/tag/v1.3.0',
  'assets': [
    for (final abi in abis)
      {
        'name': 'hormone-v1.3.0-$abi.apk',
        'browser_download_url':
            'https://github.com/Aetik-yue/hormone/releases/download/v1.3.0/hormone-v1.3.0-$abi.apk',
        'size': 123,
        'digest': 'sha256:$_hash',
      },
  ],
};

void main() {
  for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
    test('$abi 选择对应小包，使用内嵌 SHA-256 不再请求校验文件', () async {
      var requests = 0;
      final repository = GitHubReleaseRepository(
        abi: abi,
        client: MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode(
              _manifest(['android', 'x86_64', 'arm64-v8a', 'armeabi-v7a']),
            ),
            200,
          );
        }),
      );
      addTearDown(repository.close);
      final release = await repository.fetchLatestRelease();
      expect(release.apkFileName, 'hormone-v1.3.0-$abi.apk');
      expect(release.sha256, _hash);
      expect(requests, 1);
    });
  }

  test('缺少对应架构或架构未知时选择通用包', () async {
    for (final abi in ['arm64-v8a', 'unknown']) {
      final repository = GitHubReleaseRepository(
        abi: abi,
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode(_manifest(['x86_64', 'android'])), 200),
        ),
      );
      addTearDown(repository.close);
      expect(
        (await repository.fetchLatestRelease()).apkFileName,
        'hormone-v1.3.0-android.apk',
      );
    }
  });

  test('没有兼容包时不选择其他架构', () async {
    final repository = GitHubReleaseRepository(
      abi: 'arm64-v8a',
      client: MockClient(
        (_) async => http.Response(jsonEncode(_manifest(['x86_64'])), 200),
      ),
    );
    addTearDown(repository.close);
    await expectLater(
      repository.fetchLatestRelease(),
      throwsA(isA<UpdateCheckException>()),
    );
  });

  test('镜像清单只需一次请求，保留同包 GitHub 地址作为备用', () async {
    final requests = <Uri>[];
    final repository = GitHubReleaseRepository(
      abi: 'arm64-v8a',
      updateBaseUrl: 'https://updates.example.com/hormone',
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode(_manifest(['arm64-v8a', 'android'])),
          200,
        );
      }),
    );
    addTearDown(repository.close);
    final release = await repository.fetchLatestRelease();
    expect(
      requests.single.toString(),
      'https://updates.example.com/hormone/latest.json',
    );
    expect(
      release.apkUrl.toString(),
      'https://updates.example.com/hormone/v1.3.0/hormone-v1.3.0-arm64-v8a.apk',
    );
    expect(release.fallbackUrls.single.host, 'github.com');
  });

  for (final body in [
    'not json',
    '{}',
    '{"draft":true}',
    '{"prerelease":true}',
  ]) {
    test('镜像无效时回退 GitHub：$body', () async {
      final requests = <Uri>[];
      final repository = GitHubReleaseRepository(
        abi: 'arm64-v8a',
        updateBaseUrl: 'https://updates.example.com/',
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            request.url.host == 'updates.example.com'
                ? body
                : jsonEncode(_manifest(['android'])),
            200,
          );
        }),
      );
      addTearDown(repository.close);
      expect(
        (await repository.fetchLatestRelease()).apkFileName,
        'hormone-v1.3.0-android.apk',
      );
      expect(requests.map((url) => url.host), [
        'updates.example.com',
        'api.github.com',
      ]);
    });
  }
}
