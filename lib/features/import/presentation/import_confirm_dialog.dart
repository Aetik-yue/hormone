import 'package:flutter/material.dart';

import 'package:hormone/features/import/domain/import_course.dart';

/// 导入执行前的二次确认弹窗。返回 true 表示用户确认继续。
Future<bool> showImportConfirmDialog(
  BuildContext context, {
  required ImportMode mode,
  required int importCount,
  required int existingCount,
}) async {
  final isReplace = mode == ImportMode.replace;
  final message = isReplace
      ? '将删除当前学期的 $existingCount 门现有课程，导入所选 $importCount 门课程。'
          '\n\n此操作不可撤销。'
      : '将在现有 $existingCount 门课程的基础上，追加导入 $importCount 门课程。'
          '\n\n与现有课程时间冲突的条目会在预览中提示。';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isReplace ? '替换当前课表？' : '合并到当前课表？'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(isReplace ? '替换' : '追加'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}