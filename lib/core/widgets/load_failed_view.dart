import 'package:flutter/material.dart';

/// 数据加载失败状态：易懂的说明加重试入口，不展示原始异常。
///
/// 课程编辑、课表周视图与学期管理共用。重试要失效哪些数据源仍由调用方
/// 通过 [onRetry] 决定。
class LoadFailedView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const LoadFailedView({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined, size: 48, color: theme.hintColor),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
