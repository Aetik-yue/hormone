import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/github_release_repository.dart';
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
      status == AppUpdateStatus.downloading;
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
  final OtaUpdate Function() _otaUpdateFactory;
  OtaUpdate? _activeOtaUpdate;
  StreamSubscription<OtaEvent>? _subscription;

  AppUpdateController(
    this._repository, {
    OtaUpdate Function()? otaUpdateFactory,
  }) : _otaUpdateFactory = otaUpdateFactory ?? OtaUpdate.new,
       super(const AppUpdateState());

  /// 检查 GitHub 最新正式 Release。自动检查最多每天一次。
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
      state = AppUpdateState(
        status: automatic ? AppUpdateStatus.idle : AppUpdateStatus.failed,
        installedVersion: state.installedVersion,
        release: previousRelease,
        message: automatic ? null : _readableError(error),
      );
      return null;
    }
  }

  /// 下载 APK、校验 SHA-256，随后打开 Android 系统安装确认页。
  Future<void> downloadAndInstall() async {
    final release = state.release;
    if (release == null || state.isBusy) return;

    await _subscription?.cancel();
    state = AppUpdateState(
      status: AppUpdateStatus.downloading,
      installedVersion: state.installedVersion,
      release: release,
      message: '正在下载安装包…',
    );

    try {
      final otaUpdate = _otaUpdateFactory();
      _activeOtaUpdate = otaUpdate;
      _subscription = otaUpdate
          .execute(
            release.apkUrl.toString(),
            destinationFilename: release.apkFileName,
            sha256checksum: release.sha256,
          )
          .listen(
            _handleOtaEvent,
            onError: (Object error, StackTrace stackTrace) {
              _setFailure('下载更新失败：${_readableError(error)}');
            },
          );
    } catch (error) {
      _setFailure('无法开始下载：${_readableError(error)}');
    }
  }

  Future<void> cancelDownload() async {
    if (state.status != AppUpdateStatus.downloading) return;
    await _activeOtaUpdate?.cancel();
  }

  void _handleOtaEvent(OtaEvent event) {
    final release = state.release;
    if (release == null) return;

    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        final percentage = double.tryParse(event.value ?? '') ?? 0;
        state = AppUpdateState(
          status: AppUpdateStatus.downloading,
          installedVersion: state.installedVersion,
          release: release,
          progress: (percentage / 100).clamp(0, 1),
          message: '正在下载 ${percentage.round()}%',
        );
      case OtaStatus.INSTALLING:
        state = AppUpdateState(
          status: AppUpdateStatus.installing,
          installedVersion: state.installedVersion,
          release: release,
          progress: 1,
          message: '安装包校验通过，请在系统页面确认安装',
        );
      case OtaStatus.INSTALLATION_DONE:
        state = AppUpdateState(
          status: AppUpdateStatus.installing,
          installedVersion: state.installedVersion,
          release: release,
          progress: 1,
          message: '新版本安装完成',
        );
      case OtaStatus.CANCELED:
        state = AppUpdateState(
          status: AppUpdateStatus.updateAvailable,
          installedVersion: state.installedVersion,
          release: release,
          message: '已取消下载',
        );
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _setFailure('未获得安装应用权限，请允许 Hormone 安装未知来源应用后重试');
      case OtaStatus.CHECKSUM_ERROR:
        _setFailure('安装包完整性校验失败，已停止安装，请重新下载');
      case OtaStatus.DOWNLOAD_ERROR:
        _setFailure('安装包下载失败，请检查网络后重试');
      case OtaStatus.ALREADY_RUNNING_ERROR:
        _setFailure('更新任务未能继续，请关闭其他更新任务后重试');
      case OtaStatus.INSTALLATION_ERROR:
        _setFailure('更新任务未能继续，请关闭其他更新任务后重试');
      case OtaStatus.INTERNAL_ERROR:
        _setFailure(
          event.value?.isNotEmpty == true ? event.value! : '更新时发生未知错误',
        );
    }
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
    if (error is UpdateCheckException) return error.message;
    if (error is TimeoutException) return '连接超时，请检查网络后重试';
    if (error is http.ClientException) return '无法连接 GitHub，请检查网络后重试';
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
