import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/app_release.dart';

const _latestReleaseUrl =
    'https://api.github.com/repos/Aetik-yue/hormone/releases/latest';

/// GitHub Release 响应无效、缺少 APK 或校验文件时抛出的可展示异常。
class UpdateCheckException implements Exception {
  final String message;

  const UpdateCheckException(this.message);

  @override
  String toString() => message;
}

/// 从公开 GitHub Release 获取最新 Android APK 与其 SHA-256。
class GitHubReleaseRepository {
  final http.Client _client;

  GitHubReleaseRepository({http.Client? client})
    : _client = client ?? http.Client();

  Future<AppRelease> fetchLatestRelease() async {
    final response = await _client
        .get(
          Uri.parse(_latestReleaseUrl),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'Hormone-Android-Updater',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) {
      throw const UpdateCheckException('暂时还没有可用的正式版本');
    }
    if (response.statusCode != 200) {
      throw UpdateCheckException('GitHub 返回异常状态（${response.statusCode}），请稍后重试');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const UpdateCheckException('版本信息格式不正确');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const UpdateCheckException('版本信息格式不正确');
    }

    final tagName = _requiredString(decoded, 'tag_name');
    final pageUrl = _httpsUri(_requiredString(decoded, 'html_url'));
    final assets = _assets(decoded['assets']);
    final apk = _selectApk(assets);
    final checksumAsset = _selectChecksum(assets, apk.name);
    final checksum = await _fetchChecksum(checksumAsset.url, apk.name);

    try {
      return AppRelease(
        version: AppRelease.parseVersion(tagName),
        tagName: tagName,
        releaseName: _optionalString(decoded['name']) ?? tagName,
        notes: _optionalString(decoded['body'])?.trim() ?? '',
        pageUrl: pageUrl,
        apkUrl: apk.url,
        apkFileName: apk.name,
        apkSize: apk.size,
        sha256: checksum,
        publishedAt: DateTime.tryParse(
          _optionalString(decoded['published_at']) ?? '',
        ),
      );
    } on FormatException {
      throw UpdateCheckException('无法识别版本标签：$tagName');
    }
  }

  Future<String> _fetchChecksum(Uri url, String apkName) async {
    final response = await _client
        .get(url, headers: const {'User-Agent': 'Hormone-Android-Updater'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw UpdateCheckException('无法获取安装包校验值（${response.statusCode}）');
    }
    if (response.bodyBytes.length > 64 * 1024) {
      throw const UpdateCheckException('安装包校验文件过大');
    }

    final bareHashPattern = RegExp(r'^[a-fA-F0-9]{64}$');
    final namedHashPattern = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$');
    final contents = response.body.trim();
    if (bareHashPattern.hasMatch(contents)) return contents.toLowerCase();

    for (final line in const LineSplitter().convert(response.body)) {
      final match = namedHashPattern.firstMatch(line.trim());
      if (match != null && match.group(2) == apkName) {
        return match.group(1)!.toLowerCase();
      }
    }
    throw const UpdateCheckException('安装包的 SHA-256 校验值无效或未匹配当前 APK');
  }

  void close() => _client.close();
}

class _ReleaseAsset {
  final String name;
  final Uri url;
  final int size;

  const _ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });
}

List<_ReleaseAsset> _assets(Object? value) {
  if (value is! List) {
    throw const UpdateCheckException('版本中没有可下载的文件');
  }
  return value
      .whereType<Map<String, dynamic>>()
      .map((asset) {
        final name = _requiredString(asset, 'name');
        return _ReleaseAsset(
          name: name,
          url: _httpsUri(_requiredString(asset, 'browser_download_url')),
          size: asset['size'] is int ? asset['size'] as int : 0,
        );
      })
      .toList(growable: false);
}

_ReleaseAsset _selectApk(List<_ReleaseAsset> assets) {
  final candidates =
      assets
          .where(
            (asset) =>
                asset.name.toLowerCase().endsWith('.apk') &&
                !asset.name.contains('/') &&
                !asset.name.contains(r'\'),
          )
          .toList();
  if (candidates.isEmpty) {
    throw const UpdateCheckException('最新版本中没有 Android APK');
  }
  candidates.sort((a, b) {
    final aPreferred = a.name.toLowerCase().contains('android') ? 0 : 1;
    final bPreferred = b.name.toLowerCase().contains('android') ? 0 : 1;
    return aPreferred.compareTo(bPreferred);
  });
  return candidates.first;
}

_ReleaseAsset _selectChecksum(List<_ReleaseAsset> assets, String apkName) {
  final exactName = '$apkName.sha256'.toLowerCase();
  for (final asset in assets) {
    if (asset.name.toLowerCase() == exactName) return asset;
  }
  for (final asset in assets) {
    final name = asset.name.toLowerCase();
    if (name == 'sha256sums' ||
        name == 'sha256sums.txt' ||
        name == 'checksums.txt') {
      return asset;
    }
  }
  throw const UpdateCheckException('最新版本缺少 SHA-256 校验文件');
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null || value.isEmpty) {
    throw const UpdateCheckException('版本信息缺少必要字段');
  }
  return value;
}

String? _optionalString(Object? value) => value is String ? value : null;

Uri _httpsUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw const UpdateCheckException('版本下载地址不安全或无效');
  }
  return uri;
}
