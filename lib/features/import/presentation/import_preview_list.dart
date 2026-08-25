import 'package:flutter/material.dart';

import 'package:hormone/features/import/domain/import_course.dart';

/// 共享的导入预览列表：按星期分组，支持勾选与时间冲突标红。
///
/// 供文件导入（import_screen）与 WebView 教务导入共用，保证两个入口的
/// 预览交互一致。顶部的「共 N 门」「全选」等操作条由各页面自行渲染，
/// 这里只负责分组列表本体。
class ImportPreviewList extends StatelessWidget {
  final List<ImportCourse> courses;
  final Set<String> conflictedNames;
  final void Function(int index) onToggle;

  const ImportPreviewList({
    super.key,
    required this.courses,
    this.conflictedNames = const {},
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (courses.isEmpty) {
      return Center(
        child: Text('没有课程', style: theme.textTheme.bodyMedium),
      );
    }

    // 按星期分组，组内按起始节次排序，方便扫读。
    final grouped = <int, List<int>>{};
    for (var i = 0; i < courses.length; i++) {
      grouped.putIfAbsent(courses[i].dayOfWeek, () => []).add(i);
    }
    for (final indices in grouped.values) {
      indices.sort((a, b) =>
          courses[a].startSection.compareTo(courses[b].startSection));
    }
    final sortedDays = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedDays.length,
      itemBuilder: (context, dayIdx) {
        final day = sortedDays[dayIdx];
        final indices = grouped[day]!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Text(
                  _dayLabel(day),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...indices.map((i) {
                final c = courses[i];
                return ImportCoursePreviewTile(
                  course: c,
                  selected: c.selected,
                  conflicted: conflictedNames.contains(c.name),
                  onTap: () => onToggle(i),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  static String _dayLabel(int day) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return day >= 1 && day <= 7 ? '周${labels[day - 1]}' : '未知';
  }
}

/// 顶部的时间冲突提示条。传入冲突的课程名称集合，可为空（不显示）。
class ImportConflictBanner extends StatelessWidget {
  final Set<String> names;
  final String reason;

  const ImportConflictBanner({
    super.key,
    required this.names,
    this.reason = '同日同时段重叠',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '时间冲突：${names.join('、')}（$reason）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单条导入课程预览项（勾选 + 冲突标红）。
class ImportCoursePreviewTile extends StatelessWidget {
  final ImportCourse course;
  final bool selected;
  final bool conflicted;
  final VoidCallback onTap;

  const ImportCoursePreviewTile({
    super.key,
    required this.course,
    required this.selected,
    this.conflicted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = conflicted
        ? theme.colorScheme.error
        : selected
            ? theme.colorScheme.primary
            : Colors.transparent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
                  .withAlpha((0.3 * 255).round())
              : theme.colorScheme.surfaceContainerHighest
                  .withAlpha((0.3 * 255).round()),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Text(
                    [
                      course.sectionLabel,
                      course.weekLabel,
                      if (course.location != null) course.location!,
                      if (course.teacher != null) course.teacher!,
                    ].join('  ·  '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (conflicted)
              Icon(Icons.warning_amber_rounded,
                  size: 16, color: theme.colorScheme.error),
          ],
        ),
      ),
    );
  }
}