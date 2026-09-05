import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/app_update_controller.dart';
import '../domain/app_release.dart';

Future<void> showAppUpdateDialog(
  BuildContext context,
  AppRelease release,
) async {
  await showDialog<void>(
    context: context,
    builder:
        (dialogContext) => Consumer(
          builder: (context, dialogRef, child) {
            final state = dialogRef.watch(appUpdateControllerProvider);
            final activeRelease = state.release ?? release;
            final isDownloading = state.status == AppUpdateStatus.downloading;
            final isInstalling = state.status == AppUpdateStatus.installing;
            final failed = state.status == AppUpdateStatus.failed;

            return AlertDialog(
              icon: const Icon(Icons.system_update_alt_rounded),
              title: Text('发现新版本 ${activeRelease.tagName}'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 460,
                  maxHeight: 440,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state.installedVersion != null)
                        Text(
                          '当前版本 v${state.installedVersion}  ·  '
                          '${_formatBytes(activeRelease.apkSize)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (activeRelease.notes.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          '更新内容',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(activeRelease.notes),
                      ],
                      const SizedBox(height: 16),
                      if (isDownloading) ...[
                        LinearProgressIndicator(value: state.progress),
                        const SizedBox(height: 8),
                      ],
                      if (state.message != null)
                        Text(
                          state.message!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color:
                                failed
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                          ),
                        ),
                      if (!isDownloading && !isInstalling) ...[
                        const SizedBox(height: 10),
                        Text(
                          '下载完成后会打开 Android 系统安装页；首次使用可能需要允许“安装未知来源应用”。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                if (isDownloading)
                  TextButton(
                    onPressed:
                        () =>
                            dialogRef
                                .read(appUpdateControllerProvider.notifier)
                                .cancelDownload(),
                    child: const Text('取消下载'),
                  )
                else
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(isInstalling ? '完成' : '稍后'),
                  ),
                if (!isDownloading && !isInstalling)
                  TextButton(
                    onPressed:
                        () => launchUrl(
                          activeRelease.pageUrl,
                          mode: LaunchMode.externalApplication,
                        ),
                    child: const Text('发布页面'),
                  ),
                FilledButton.icon(
                  onPressed:
                      isDownloading || isInstalling
                          ? null
                          : () =>
                              dialogRef
                                  .read(appUpdateControllerProvider.notifier)
                                  .downloadAndInstall(),
                  icon:
                      isDownloading
                          ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.download_rounded),
                  label: Text(
                    isDownloading
                        ? '${(state.progress * 100).round()}%'
                        : failed
                        ? dialogRef
                                .read(appUpdateControllerProvider.notifier)
                                .hasDownloadedApk
                            ? '重试安装'
                            : '重新下载'
                        : isInstalling
                        ? '等待安装'
                        : '下载并安装',
                  ),
                ),
              ],
            );
          },
        ),
  );
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '大小未知';
  final megabytes = bytes / (1024 * 1024);
  return '${megabytes.toStringAsFixed(megabytes >= 10 ? 1 : 2)} MB';
}
