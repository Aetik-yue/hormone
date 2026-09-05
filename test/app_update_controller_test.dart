import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/update/application/app_update_controller.dart';
import 'package:hormone/features/update/data/github_release_repository.dart';
import 'package:hormone/features/update/domain/app_release.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hormone/features/update/data/update_downloader.dart';
import 'package:hormone/features/update/data/update_installer.dart';
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
    final downloader = _FakeDownloader();
    final installer = _FakeInstaller();
    final controller = AppUpdateController(
      repository,
      downloader: downloader,
      installer: installer,
    );

    final release = await controller.checkForUpdate();
    expect(release?.tagName, 'v1.3.0');
    expect(controller.state.status, AppUpdateStatus.updateAvailable);

    final job = controller.downloadAndInstall();
    await pumpEventQueue();
    expect(controller.state.status, AppUpdateStatus.downloading);
    expect(downloader.release?.sha256, release?.sha256);

    downloader.onProgress!(const UpdateDownloadProgress(42, 100, 1024, 0, 1));
    await pumpEventQueue();
    expect(controller.state.progress, closeTo(0.42, 0.001));

    downloader.completer.complete(File('verified.apk'));
    await job;
    expect(installer.installCount, 1);
    expect(controller.state.status, AppUpdateStatus.installing);

    controller.dispose();
    repository.close();
  });

  test('取消下载后不调用安装器，也不自动重启下载', () async {
    final repository = _FakeReleaseRepository(_release('v1.3.0'));
    final downloader = _FakeDownloader();
    final installer = _FakeInstaller();
    final controller = AppUpdateController(
      repository,
      downloader: downloader,
      installer: installer,
    );
    await controller.checkForUpdate();
    final job = controller.downloadAndInstall();
    await pumpEventQueue();
    await controller.cancelDownload();
    await job;
    expect(controller.state.status, AppUpdateStatus.updateAvailable);
    expect(installer.installCount, 0);
    expect(downloader.calls, 1);
    controller.dispose();
    repository.close();
  });

  test('连续点击下载只启动一个任务', () async {
    final repository = _FakeReleaseRepository(_release('v1.3.0'));
    final downloader = _FakeDownloader();
    final installer = _FakeInstaller();
    final controller = AppUpdateController(
      repository,
      downloader: downloader,
      installer: installer,
    );
    await controller.checkForUpdate();
    final job = controller.downloadAndInstall();
    await controller.downloadAndInstall();
    expect(downloader.calls, 1);
    downloader.completer.complete(File('verified.apk'));
    await job;
    expect(installer.installCount, 1);
    controller.dispose();
    repository.close();
  });

  test('校验失败不会调用安装器', () async {
    final repository = _FakeReleaseRepository(_release('v1.3.0'));
    final downloader = _FakeDownloader();
    final installer = _FakeInstaller();
    final controller = AppUpdateController(
      repository,
      downloader: downloader,
      installer: installer,
    );
    await controller.checkForUpdate();
    final job = controller.downloadAndInstall();
    downloader.completer.completeError(const UpdateDownloadException('校验失败'));
    await job;
    expect(controller.state.status, AppUpdateStatus.failed);
    expect(installer.installCount, 0);
    controller.dispose();
    repository.close();
  });

  test('授权后复用已经下载的 APK 重试安装', () async {
    final directory = await Directory.systemTemp.createTemp(
      'hormone-install-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final apk = await File(
      '${directory.path}/update.apk',
    ).writeAsString('verified');
    final repository = _FakeReleaseRepository(_release('v1.3.0'));
    final downloader = _FakeDownloader();
    final installer = _FakeInstaller()..allowed = false;
    final controller = AppUpdateController(
      repository,
      downloader: downloader,
      installer: installer,
    );
    await controller.checkForUpdate();
    final job = controller.downloadAndInstall();
    downloader.completer.complete(apk);
    await job;
    expect(controller.state.status, AppUpdateStatus.failed);
    expect(controller.hasDownloadedApk, isTrue);
    installer.allowed = true;
    await controller.downloadAndInstall();
    expect(controller.state.status, AppUpdateStatus.installing);
    expect(downloader.calls, 1);
    expect(installer.installCount, 2);
    controller.dispose();
    repository.close();
  });

  test('销毁控制器后下载回调不会触发安装或修改状态', () async {
    final repository = _FakeReleaseRepository(_release('v1.3.0'));
    final downloader = _FakeDownloader();
    final installer = _FakeInstaller();
    final controller = AppUpdateController(
      repository,
      downloader: downloader,
      installer: installer,
    );
    await controller.checkForUpdate();
    final job = controller.downloadAndInstall();
    controller.dispose();
    await job;
    expect(installer.installCount, 0);
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

class _FakeDownloader extends UpdateDownloader {
  final completer = Completer<File>();
  AppRelease? release;
  void Function(UpdateDownloadProgress)? onProgress;
  int calls = 0;

  @override
  Future<File> download(
    AppRelease release,
    void Function(UpdateDownloadProgress) onProgress,
  ) {
    calls++;
    this.release = release;
    this.onProgress = onProgress;
    return completer.future;
  }

  @override
  void cancel() {
    if (calls > 0 && !completer.isCompleted)
      completer.completeError(UpdateDownloadCanceled());
  }
}

class _FakeInstaller extends UpdateInstaller {
  int installCount = 0;
  bool allowed = true;

  @override
  Future<bool> install(File apk) async {
    installCount++;
    return allowed;
  }
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
