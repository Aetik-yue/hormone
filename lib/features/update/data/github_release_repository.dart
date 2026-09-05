import 'dart:convert';
import 'dart:ffi';

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
  final String? _abi;
  final Uri? _mirrorBase;

  GitHubReleaseRepository({
    http.Client? client,
    String? abi,
    String updateBaseUrl = const String.fromEnvironment(
      'HORMONE_UPDATE_BASE_URL',
    ),
  }) : _client = client ?? http.Client(),
       _abi = abi ?? _currentAbi(),
       _mirrorBase = _parseMirrorBase(updateBaseUrl);

  Future<AppRelease> fetchLatestRelease() async {
    final mirror = _mirrorBase;
    if (mirror != null) {
      try {
        return await _fetchRelease(mirror.resolve('latest.json'), mirror: true);
      } on Exception {
        // 镜像未配置完成、离线或清单损坏时仍能从 GitHub 更新。
      }
    }
    return _fetchRelease(Uri.parse(_latestReleaseUrl));
  }

  Future<AppRelease> _fetchRelease(Uri url, {bool mirror = false}) async {
    final response = await _client
        .get(
          url,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'Hormone-Android-Updater',
          },
        )
        .timeout(Duration(seconds: mirror ? 5 : 15));

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
    if (decoded['draft'] == true || decoded['prerelease'] == true) {
      throw const UpdateCheckException('更新源未提供正式版本');
    }

    final tagName = _requiredString(decoded, 'tag_name');
    final pageUrl = _httpsUri(_requiredString(decoded, 'html_url'));
    final assets = _assets(decoded['assets']);
    final apk = _selectApk(assets, _abi, tagName);
    final checksum =
        apk.sha256 ??
        await _fetchChecksum(_selectChecksum(assets, apk.name).url, apk.name);
    final downloadUrl =
        _mirrorBase?.resolve(
          '${Uri.encodeComponent(tagName)}/${Uri.encodeComponent(apk.name)}',
        ) ??
        apk.url;

    try {
      return AppRelease(
        version: AppRelease.parseVersion(tagName),
        tagName: tagName,
        releaseName: _optionalString(decoded['name']) ?? tagName,
        notes: _optionalString(decoded['body'])?.trim() ?? '',
        pageUrl: pageUrl,
        apkUrl: downloadUrl,
        fallbackUrls: downloadUrl == apk.url ? const [] : [apk.url],
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
  final String? sha256;

  const _ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
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
          sha256: _digest(asset['digest']),
        );
      })
      .toList(growable: false);
}

_ReleaseAsset _selectApk(List<_ReleaseAsset> assets, String? abi, String tag) {
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
  // 分架构包使用固定名称，不含 android，兼容旧版的通用包优先规则。
  if (abi != null) {
    for (final candidate in candidates) {
      if (candidate.name == 'hormone-$tag-$abi.apk') return candidate;
    }
  }
  final universal =
      candidates
          .where(
            (asset) =>
                asset.name == 'hormone-$tag-android.apk' ||
                asset.name == 'app-release.apk' ||
                asset.name == 'app.apk' ||
                asset.name == 'fallback.apk',
          )
          .toList();
  if (universal.isEmpty) {
    throw const UpdateCheckException('最新版本中没有适合当前设备的安装包');
  }
  universal.sort((a, b) {
    final aPreferred = a.name.toLowerCase().contains('android') ? 0 : 1;
    final bPreferred = b.name.toLowerCase().contains('android') ? 0 : 1;
    return aPreferred.compareTo(bPreferred);
  });
  return universal.first;
}

String? _currentAbi() => switch (Abi.current()) {
  Abi.androidArm64 => 'arm64-v8a',
  Abi.androidArm => 'armeabi-v7a',
  Abi.androidX64 => 'x86_64',
  _ => null,
};

String? _digest(Object? value) {
  if (value is! String) return null;
  return RegExp(
    r'^sha256:([a-fA-F0-9]{64})$',
  ).firstMatch(value)?.group(1)?.toLowerCase();
}

Uri? _parseMirrorBase(String value) {
  if (value.trim().isEmpty) return null;
  final uri = _httpsUri(value.trim());
  if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) {
    throw const UpdateCheckException('更新源必须是无查询参数的 HTTPS 目录地址');
  }
  return uri.replace(path: uri.path.endsWith('/') ? uri.path : '${uri.path}/');
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
