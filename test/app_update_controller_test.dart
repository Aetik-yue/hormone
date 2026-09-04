import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/update/application/app_update_controller.dart';
import 'package:hormone/features/update/data/github_release_repository.dart';
import 'package:hormone/features/update/domain/app_release.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Hormone',
      packageName: 'com.aetikyue.hormone',
      version: '1.2.2',
      buildNumber: '22',
      buildSignature: 'test',
    );
  });

  test('检查到新版本后更新下载进度并进入安装状态', () async {
    final repository = _FakeReleaseRepository(_release('v1.3.0'));
    final otaUpdate = _FakeOtaUpdate();
    final controller = AppUpdateController(
      repository,
      otaUpdateFactory: () => otaUpdate,
    );

    final release = await controller.checkForUpdate();
    expect(release?.tagName, 'v1.3.0');
    expect(controller.state.status, AppUpdateStatus.updateAvailable);

    await controller.downloadAndInstall();
    expect(controller.state.status, AppUpdateStatus.downloading);
    expect(otaUpdate.requestedChecksum, release?.sha256);

    otaUpdate.events.add(OtaEvent(OtaStatus.DOWNLOADING, '42'));
    await pumpEventQueue();
    expect(controller.state.progress, closeTo(0.42, 0.001));

    otaUpdate.events.add(OtaEvent(OtaStatus.INSTALLING, null));
    await pumpEventQueue();
    expect(controller.state.status, AppUpdateStatus.installing);

    controller.dispose();
    await otaUpdate.dispose();
    repository.close();
  });

  test('自动检查在 24 小时内只请求一次 GitHub', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'app_update_last_automatic_check': now,
    });
    final repository = _FakeReleaseRepository(_release('v1.3.0'));
    final controller = AppUpdateController(repository);

    final release = await controller.checkForUpdate(automatic: true);

    expect(release, isNull);
    expect(repository.fetchCount, 0);
    expect(controller.state.status, AppUpdateStatus.idle);
    controller.dispose();
    repository.close();
  });

  test('相同版本显示已是最新且不会保留为可下载更新', () async {
    final repository = _FakeReleaseRepository(_release('v1.2.2'));
    final controller = AppUpdateController(repository);

    final release = await controller.checkForUpdate();

    expect(release, isNull);
    expect(controller.state.status, AppUpdateStatus.upToDate);
    expect(controller.state.release, isNull);
    controller.dispose();
    repository.close();
  });

  test('同时触发检查时不会重复请求或重复返回更新弹窗', () async {
    final repository = _FakeReleaseRepository(_release('v1.3.0'));
    final controller = AppUpdateController(repository);

    final releases = await Future.wait([
      controller.checkForUpdate(),
      controller.checkForUpdate(),
    ]);

    expect(repository.fetchCount, 1);
    expect(releases.whereType<AppRelease>(), hasLength(1));
    controller.dispose();
    repository.close();
  });
}

class _FakeReleaseRepository extends GitHubReleaseRepository {
  final AppRelease nextRelease;
  int fetchCount = 0;

  _FakeReleaseRepository(this.nextRelease)
    : super(client: MockClient((_) async => http.Response('', 500)));

  @override
  Future<AppRelease> fetchLatestRelease() async {
    fetchCount++;
    return nextRelease;
  }
}

class _FakeOtaUpdate extends OtaUpdate {
  final events = StreamController<OtaEvent>.broadcast();
  String? requestedChecksum;

  @override
  Stream<OtaEvent> execute(
    String url, {
    Map<String, String> headers = const <String, String>{},
    String? androidProviderAuthority,
    String? destinationFilename,
    String? sha256checksum,
    bool usePackageInstaller = false,
  }) {
    requestedChecksum = sha256checksum;
    return events.stream;
  }

  @override
  Future<void> cancel() async {
    events.add(OtaEvent(OtaStatus.CANCELED, null));
  }

  Future<void> dispose() => events.close();
}

AppRelease _release(String tag) => AppRelease(
  version: AppRelease.parseVersion(tag),
  tagName: tag,
  releaseName: tag,
  notes: '更新内容',
  pageUrl: Uri.parse('https://github.com/Aetik-yue/hormone/releases'),
  apkUrl: Uri.parse('https://github.com/Aetik-yue/hormone/app.apk'),
  apkFileName: 'hormone-v1.3.0-android.apk',
  apkSize: 42,
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  publishedAt: null,
);
