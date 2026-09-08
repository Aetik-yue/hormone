import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/github_release_repository.dart';
import '../data/update_downloader.dart';
import '../data/update_installer.dart';
import '../domain/app_release.dart';

enum AppUpdateStatus {
  idle,
  checking,
  updateAvailable,
  upToDate,
  downloading,
  installing,
  failed,
}

class AppUpdateState {
  final AppUpdateStatus status;
  final String? installedVersion;
  final AppRelease? release;
  final double progress;
  final String? message;

  const AppUpdateState({
    this.status = AppUpdateStatus.idle,
    this.installedVersion,
    this.release,
    this.progress = 0,
    this.message,
  });

  bool get isBusy =>
      status == AppUpdateStatus.checking ||
      status == AppUpdateStatus.downloading ||
      status == AppUpdateStatus.installing;
}

final githubReleaseRepositoryProvider = Provider<GitHubReleaseRepository>((
  ref,
) {
  final repository = GitHubReleaseRepository();
  ref.onDispose(repository.close);
  return repository;
});

final appUpdateControllerProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
      return AppUpdateController(ref.read(githubReleaseRepositoryProvider));
    });

class AppUpdateController extends StateNotifier<AppUpdateState> {
  static const _lastAutomaticCheckKey = 'app_update_last_automatic_check';
  static const _automaticCheckInterval = Duration(hours: 24);

  final GitHubReleaseRepository _repository;
  final UpdateDownloader _downloader;
  final UpdateInstaller _installer;
  Future<void>? _downloadJob;
  bool _cancelRequested = false;
  File? _downloadedApk;
  String? _downloadedChecksum;

  AppUpdateController(
    this._repository, {
    UpdateDownloader? downloader,
    UpdateInstaller? installer,
  }) : _downloader = downloader ?? UpdateDownloader(),
       _installer = installer ?? UpdateInstaller(),
       super(const AppUpdateState());

  /// 检查更新源的最新正式版本。自动检查最多每天一次。
  Future<AppRelease?> checkForUpdate({bool automatic = false}) async {
    if (state.isBusy) return null;

    final previousState = state;
    final previousRelease = state.release;
    state = AppUpdateState(
      status: AppUpdateStatus.checking,
      installedVersion: state.installedVersion,
      release: previousRelease,
    );

    try {
      if (automatic) {
        final prefs = await SharedPreferences.getInstance();
        final lastMillis = prefs.getInt(_lastAutomaticCheckKey);
        if (lastMillis != null) {
          final last = DateTime.fromMillisecondsSinceEpoch(lastMillis);
          if (DateTime.now().difference(last) < _automaticCheckInterval) {
            state = previousState;
            return null;
          }
        }
        await prefs.setInt(
          _lastAutomaticCheckKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final release = await _repository.fetchLatestRelease();
      if (!mounted) return null;
      if (release.isNewerThan(packageInfo.version)) {
        state = AppUpdateState(
          status: AppUpdateStatus.updateAvailable,
          installedVersion: packageInfo.version,
          release: release,
          message: '发现新版本 ${release.tagName}',
        );
        return release;
      }

      state = AppUpdateState(
        status: AppUpdateStatus.upToDate,
        installedVersion: packageInfo.version,
        message: '当前已是最新版本',
      );
      return null;
    } catch (error) {
      if (!mounted) return null;
      state = AppUpdateState(
        status: automatic ? AppUpdateStatus.idle : AppUpdateStatus.failed,
        installedVersion: state.installedVersion,
        release: previousRelease,
        message: automatic ? null : _readableError(error),
      );
      return null;
    }
  }

  /// 下载、校验与安装分开，切换线路不会触发旧下载的安装回调。
  Future<void> downloadAndInstall() {
    final release = state.release;
    if (release == null || state.isBusy || _downloadJob != null) {
      return Future.value();
    }
    _cancelRequested = false;
    state = AppUpdateState(
      status: AppUpdateStatus.downloading,
      installedVersion: state.installedVersion,
      release: release,
      message: '正在连接下载源…',
    );
    final job = _downloadAndInstall(release);
    _downloadJob = job;
    return job.whenComplete(() => _downloadJob = null);
  }

  Future<void> _downloadAndInstall(AppRelease release) async {
    try {
      if (_downloadedChecksum != release.sha256 ||
          _downloadedApk == null ||
          !await _downloadedApk!.exists()) {
        if (!mounted || _cancelRequested) return;
        final apk = await _downloader.download(release, (progress) {
          if (!mounted || _cancelRequested) return;
          final fraction =
              progress.total > 0
                  ? (progress.received / progress.total).clamp(0.0, 1.0)
                  : 0.0;
          final source = progress.sourceIndex > 0 ? '已切换备用源 · ' : '';
          final speed =
              progress.bytesPerSecond >= 1024 * 1024
                  ? '${(progress.bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s'
                  : '${(progress.bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
          state = AppUpdateState(
            status: AppUpdateStatus.downloading,
            installedVersion: state.installedVersion,
            release: release,
            progress: fraction,
            message:
                fraction >= 1
                    ? '下载完成，正在校验安装包…'
                    : '${source}正在下载 ${(fraction * 100).round()}% · $speed',
          );
        });
        _downloadedApk = apk;
        _downloadedChecksum = release.sha256;
      }
      if (!mounted || _cancelRequested) return;
      // 授权失败时保留私有目录中的已校验文件，重试安装无需再下载。
      state = AppUpdateState(
        status: AppUpdateStatus.installing,
        installedVersion: state.installedVersion,
        release: release,
        progress: 1,
        message: '正在打开系统安装页…',
      );
      final opened = await _installer.install(_downloadedApk!);
      if (!mounted || _cancelRequested) return;
      state = AppUpdateState(
        status:
            opened ? AppUpdateStatus.updateAvailable : AppUpdateStatus.failed,
        installedVersion: state.installedVersion,
        release: release,
        progress: 1,
        message:
            opened
                ? '请在系统页面确认安装；如果取消或安装未完成，返回后可点“重试安装”'
                : '请允许 Hormone 安装未知来源应用，返回后点“重试安装”',
      );
    } on UpdateDownloadCanceled {
      // cancelDownload 统一在下载退出后恢复状态。
    } catch (error) {
      if (mounted && !_cancelRequested) _setFailure(_readableError(error));
    }
  }

  bool get hasDownloadedApk =>
      _downloadedApk != null && _downloadedChecksum == state.release?.sha256;

  Future<void> cancelDownload() async {
    if (state.status != AppUpdateStatus.downloading) return;
    _cancelRequested = true;
    _downloader.cancel();
    await _downloadJob;
    if (!mounted) return;
    state = AppUpdateState(
      status: AppUpdateStatus.updateAvailable,
      installedVersion: state.installedVersion,
      release: state.release,
      message: '已取消下载',
    );
  }

  void _setFailure(String message) {
    state = AppUpdateState(
      status: AppUpdateStatus.failed,
      installedVersion: state.installedVersion,
      release: state.release,
      progress: state.progress,
      message: message,
    );
  }

  String _readableError(Object error) {
    if (error is UpdateDownloadException) return error.message;
    if (error is UpdateCheckException) return error.message;
    if (error is TimeoutException) return '连接超时，请检查网络后重试';
    if (error is http.ClientException) return '无法连接 GitHub，请检查网络后重试';
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    _cancelRequested = true;
    _downloader.cancel();
    super.dispose();
  }
}
