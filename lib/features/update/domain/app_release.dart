import 'package:pub_semver/pub_semver.dart';

/// 可供应用内升级的 GitHub Release。
class AppRelease {
  final Version version;
  final String tagName;
  final String releaseName;
  final String notes;
  final Uri pageUrl;
  final Uri apkUrl;
  final List<Uri> fallbackUrls;
  final String apkFileName;
  final int apkSize;
  final String sha256;
  final DateTime? publishedAt;

  const AppRelease({
    required this.version,
    required this.tagName,
    required this.releaseName,
    required this.notes,
    required this.pageUrl,
    required this.apkUrl,
    this.fallbackUrls = const [],
    required this.apkFileName,
    required this.apkSize,
    required this.sha256,
    required this.publishedAt,
  });

  /// GitHub 标签约定为 `vX.Y.Z`，同时兼容没有 `v` 的标签。
  static Version parseVersion(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
    return Version.parse(normalized);
  }

  bool isNewerThan(String installedVersion) =>
      version > parseVersion(installedVersion);

  List<Uri> get downloadUrls => [apkUrl, ...fallbackUrls].toSet().toList();
}
