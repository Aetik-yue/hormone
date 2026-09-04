import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/update/domain/app_release.dart';

void main() {
  group('AppRelease 版本比较', () {
    test('兼容带 v 和不带 v 的语义版本', () {
      expect(AppRelease.parseVersion('v1.2.3').toString(), '1.2.3');
      expect(AppRelease.parseVersion('1.2.3').toString(), '1.2.3');
    });

    test('只把更高的正式版本识别为更新', () {
      final release = _release('v1.3.0');

      expect(release.isNewerThan('1.2.9'), isTrue);
      expect(release.isNewerThan('1.3.0'), isFalse);
      expect(release.isNewerThan('1.4.0'), isFalse);
    });
  });
}

AppRelease _release(String tag) => AppRelease(
      version: AppRelease.parseVersion(tag),
      tagName: tag,
      releaseName: tag,
      notes: '',
      pageUrl: Uri.parse('https://github.com/Aetik-yue/hormone/releases'),
      apkUrl: Uri.parse('https://github.com/Aetik-yue/hormone/app.apk'),
      apkFileName: 'app.apk',
      apkSize: 1,
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      publishedAt: null,
    );
