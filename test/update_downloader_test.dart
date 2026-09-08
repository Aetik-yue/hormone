import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/update/data/update_downloader.dart';
import 'package:hormone/features/update/domain/app_release.dart';
import 'package:hormone/features/update/domain/slow_download_detector.dart';
import 'package:http/http.dart' as http;

void main() {
  final bytes = utf8.encode('a verified APK fixture');
  late Directory directory;
  late AppRelease release;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hormone-update-test-');
    release = AppRelease(
      version: AppRelease.parseVersion('v1.3.0'),
      tagName: 'v1.3.0',
      releaseName: '',
      notes: '',
      pageUrl: Uri.parse('https://github.com/Aetik-yue/hormone/releases'),
      apkUrl: Uri.parse('https://updates.example.com/app.apk'),
      fallbackUrls: [Uri.parse('https://github.com/Aetik-yue/hormone/app.apk')],
      apkFileName: 'app.apk',
      apkSize: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      publishedAt: null,
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test('首选源成功：流式写入、校验、仅保留完整 APK', () async {
    final client = _Client(
      (_) async => http.StreamedResponse(Stream.value(bytes), 200),
    );
    final downloader = UpdateDownloader(
      clientFactory: () => client,
      directory: () async => directory,
    );
    final progress = <UpdateDownloadProgress>[];
    final apk = await downloader.download(release, progress.add);
    expect(await apk.readAsBytes(), bytes);
    expect(client.closed, isTrue);
    expect(progress.last.received, bytes.length);
    expect(await File('${apk.path}.part').exists(), isFalse);
  });

  test('首选源 HTTP 失败后关闭连接，从备用源下载同一 APK', () async {
    final clients = <_Client>[];
    final downloader = UpdateDownloader(
      directory: () async => directory,
      clientFactory: () {
        if (clients.isNotEmpty) expect(clients.last.closed, isTrue);
        final client = _Client(
          (request) async =>
              request.url.host == 'github.com'
                  ? http.StreamedResponse(Stream.value(bytes), 200)
                  : http.StreamedResponse(const Stream.empty(), 503),
        );
        clients.add(client);
        return client;
      },
    );
    final progress = <UpdateDownloadProgress>[];
    final apk = await downloader.download(release, progress.add);
    expect(await apk.readAsBytes(), bytes);
    expect(clients, hasLength(2));
    expect(progress.last.sourceIndex, 1);
  });

  test('实际字节停滞时切换；部分文件不会拼到下一条线路', () async {
    final stalled = StreamController<List<int>>();
    addTearDown(stalled.close);
    var attempts = 0;
    final downloader = UpdateDownloader(
      directory: () async => directory,
      stallTimeout: const Duration(milliseconds: 20),
      clientFactory:
          () => _Client((_) async {
            attempts++;
            if (attempts == 1) {
              stalled.add(bytes.sublist(0, 2));
              return http.StreamedResponse(stalled.stream, 200);
            }
            return http.StreamedResponse(Stream.value(bytes), 200);
          }),
    );
    final apk = await downloader.download(release, (_) {});
    expect(await apk.readAsBytes(), bytes);
    expect(attempts, 2);
  });

  test('连接超时后切换备用源', () async {
    var attempts = 0;
    final downloader = UpdateDownloader(
      directory: () async => directory,
      connectionTimeout: const Duration(milliseconds: 20),
      clientFactory:
          () => _Client((_) {
            attempts++;
            return attempts == 1
                ? Completer<http.StreamedResponse>().future
                : Future.value(http.StreamedResponse(Stream.value(bytes), 200));
          }),
    );
    expect(
      await (await downloader.download(release, (_) {})).readAsBytes(),
      bytes,
    );
    expect(attempts, 2);
  });

  test('持续有数据的低速源也会切换，切换前关闭旧连接', () async {
    final clients = <_Client>[];
    final downloader = UpdateDownloader(
      directory: () async => directory,
      slowDownloadDetectorFactory:
          () => SlowDownloadDetector(
            warmup: const Duration(milliseconds: 10),
            window: const Duration(milliseconds: 10),
            slowDuration: const Duration(milliseconds: 10),
            sampleInterval: const Duration(milliseconds: 1),
            minimumBytesPerSecond: 100000,
            minimumRemainingBytes: 0,
            completionThreshold: 1,
          ),
      clientFactory: () {
        if (clients.isNotEmpty) expect(clients.last.closed, isTrue);
        final isFirst = clients.isEmpty;
        final client = _Client(
          (_) async => http.StreamedResponse(
            isFirst
                ? Stream<List<int>>.periodic(
                  const Duration(milliseconds: 10),
                  (index) => [bytes[index]],
                ).take(bytes.length)
                : Stream.value(bytes),
            200,
          ),
        );
        clients.add(client);
        return client;
      },
    );
    final apk = await downloader.download(release, (_) {});
    expect(await apk.readAsBytes(), bytes);
    expect(clients, hasLength(2));
  });

  test('最后一条可用源不启用低速切换', () async {
    var attempts = 0;
    var detectors = 0;
    final downloader = UpdateDownloader(
      directory: () async => directory,
      slowDownloadDetectorFactory: () {
        detectors++;
        return SlowDownloadDetector();
      },
      clientFactory:
          () => _Client((_) async {
            attempts++;
            return attempts == 1
                ? http.StreamedResponse(const Stream.empty(), 503)
                : http.StreamedResponse(Stream.value(bytes), 200);
          }),
    );
    expect(
      await (await downloader.download(release, (_) {})).readAsBytes(),
      bytes,
    );
    expect(attempts, 2);
    expect(detectors, 0);
  });

  test('空数据事件不会延长断流等待', () async {
    var attempts = 0;
    final downloader = UpdateDownloader(
      directory: () async => directory,
      stallTimeout: const Duration(milliseconds: 20),
      clientFactory:
          () => _Client((_) async {
            attempts++;
            return http.StreamedResponse(
              attempts == 1
                  ? Stream<List<int>>.periodic(
                    const Duration(milliseconds: 5),
                    (_) => [],
                  )
                  : Stream.value(bytes),
              200,
            );
          }),
    );
    expect(
      await (await downloader.download(release, (_) {})).readAsBytes(),
      bytes,
    );
    expect(attempts, 2);
  });

  test('所有源校验失败时拒绝返回 APK，并删除部分文件', () async {
    final downloader = UpdateDownloader(
      directory: () async => directory,
      clientFactory:
          () => _Client(
            (_) async => http.StreamedResponse(
              Stream.value(List.filled(bytes.length, 0)),
              200,
            ),
          ),
    );
    await expectLater(
      downloader.download(release, (_) {}),
      throwsA(
        isA<UpdateDownloadException>().having(
          (e) => e.message,
          'message',
          contains('校验'),
        ),
      ),
    );
    expect(
      await Directory('${directory.path}/hormone_updates').list().toList(),
      isEmpty,
    );
  });

  test('截断的下载不能通过校验', () async {
    final downloader = UpdateDownloader(
      directory: () async => directory,
      clientFactory:
          () => _Client(
            (_) async =>
                http.StreamedResponse(Stream.value(bytes.sublist(0, 3)), 200),
          ),
    );
    await expectLater(
      downloader.download(release, (_) {}),
      throwsA(isA<UpdateDownloadException>()),
    );
  });

  test('取消关闭连接、清理部分文件且不切换备用源', () async {
    var attempts = 0;
    late UpdateDownloader downloader;
    final client = _Client((_) async {
      attempts++;
      return http.StreamedResponse(Stream.value(bytes), 200);
    });
    downloader = UpdateDownloader(
      directory: () async => directory,
      clientFactory: () => client,
    );
    await expectLater(
      downloader.download(release, (progress) {
        if (progress.received > 0) downloader.cancel();
      }),
      throwsA(isA<UpdateDownloadCanceled>()),
    );
    expect(client.closed, isTrue);
    expect(attempts, 1);
    expect(
      await Directory('${directory.path}/hormone_updates').list().toList(),
      isEmpty,
    );
  });
}

class _Client extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  bool closed = false;
  _Client(this.handler);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() => closed = true;
}
