import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../domain/app_release.dart';
import '../domain/slow_download_detector.dart';

class UpdateDownloadCanceled implements Exception {}

class UpdateDownloadException implements Exception {
  final String message;
  const UpdateDownloadException(this.message);
}

class UpdateDownloadProgress {
  final int received;
  final int total;
  final double bytesPerSecond;
  final int sourceIndex;
  final int sourceCount;

  const UpdateDownloadProgress(
    this.received,
    this.total,
    this.bytesPerSecond,
    this.sourceIndex,
    this.sourceCount,
  );
}

/// 每条线路使用独立连接；按真实字节活动计时，停止旧连接后才尝试下一条。
class UpdateDownloader {
  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _directory;
  final SlowDownloadDetector Function() _slowDownloadDetectorFactory;
  final Duration connectionTimeout;
  final Duration stallTimeout;
  http.Client? _activeClient;
  bool _canceled = false;

  UpdateDownloader({
    http.Client Function()? clientFactory,
    Future<Directory> Function()? directory,
    SlowDownloadDetector Function()? slowDownloadDetectorFactory,
    this.connectionTimeout = const Duration(seconds: 15),
    this.stallTimeout = const Duration(seconds: 30),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _directory = directory ?? getTemporaryDirectory,
       _slowDownloadDetectorFactory =
           slowDownloadDetectorFactory ?? SlowDownloadDetector.new;

  void cancel() {
    _canceled = true;
    _activeClient?.close();
  }

  void _checkCanceled() {
    if (_canceled) throw UpdateDownloadCanceled();
  }

  Future<File> download(
    AppRelease release,
    void Function(UpdateDownloadProgress) onProgress,
  ) async {
    _canceled = false;
    final directory = await _directory();
    _checkCanceled();
    final folder = Directory('${directory.path}/hormone_updates');
    await folder.create(recursive: true);
    // 固定文件名，不将远程文件名用作本地路径。
    final partial = File('${folder.path}/update.apk.part');
    final verified = File('${folder.path}/update.apk');
    final urls = release.downloadUrls;
    String failure = '安装包下载失败，请检查网络后重试';
    for (var index = 0; index < urls.length; index++) {
      _checkCanceled();
      final client = _clientFactory();
      _activeClient = client;
      RandomAccessFile? output;
      try {
        onProgress(
          UpdateDownloadProgress(0, release.apkSize, 0, index, urls.length),
        );
        final response = await client
            .send(
              http.Request('GET', urls[index])
                ..headers['User-Agent'] = 'Hormone-Android-Updater',
            )
            .timeout(connectionTimeout);
        _checkCanceled();
        if (response.statusCode != 200) {
          throw const UpdateDownloadException('下载源暂不可用');
        }
        final total =
            release.apkSize > 0 ? release.apkSize : response.contentLength ?? 0;
        var received = 0;
        var lastReport = 0;
        final stopwatch = Stopwatch()..start();
        final slowDownload =
            index + 1 < urls.length ? _slowDownloadDetectorFactory() : null;
        output = await partial.open(mode: FileMode.write);
        await for (final bytes in response.stream
            .where((bytes) => bytes.isNotEmpty)
            .timeout(stallTimeout)) {
          _checkCanceled();
          received += bytes.length;
          if (total > 0 && received > total) {
            throw const UpdateDownloadException('安装包大小与版本信息不符');
          }
          await output.writeFrom(bytes);
          if (slowDownload?.shouldSwitch(
                elapsed: stopwatch.elapsed,
                received: received,
                total: total,
              ) ??
              false) {
            throw const UpdateDownloadException('当前下载源持续低速，正在尝试备用源');
          }
          final elapsed = stopwatch.elapsedMilliseconds;
          if (elapsed - lastReport >= 250 || received == total) {
            onProgress(
              UpdateDownloadProgress(
                received,
                total,
                elapsed > 0 ? received * 1000 / elapsed : 0,
                index,
                urls.length,
              ),
            );
            lastReport = elapsed;
          }
        }
        await output.close();
        output = null;
        _checkCanceled();
        if (received == 0 || (total > 0 && received != total)) {
          throw const UpdateDownloadException('安装包未下载完整');
        }
        final hash = await sha256.bind(partial.openRead()).first;
        _checkCanceled();
        if (hash.toString() != release.sha256.toLowerCase()) {
          throw const UpdateDownloadException('安装包完整性校验失败，已停止安装');
        }
        if (await verified.exists()) await verified.delete();
        await partial.rename(verified.path);
        _checkCanceled();
        return verified;
      } on Exception catch (error) {
        _checkCanceled();
        failure = switch (error) {
          UpdateDownloadException() => error.message,
          TimeoutException() => '下载连接超时或长时间无进展，请稍后重试',
          _ => '安装包下载失败，请检查网络后重试',
        };
      } finally {
        client.close();
        _activeClient = null;
        await output?.close();
        if (await partial.exists()) await partial.delete();
      }
    }
    throw UpdateDownloadException(failure);
  }
}
