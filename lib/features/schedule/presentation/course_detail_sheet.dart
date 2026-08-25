import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';

const _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

/// 弹出课程详情底部弹层（课程表点击与搜索结果共用）。
///
/// [onJumpToWeek] 非空时额外显示「跳到本周」按钮（搜索场景跳转到该课所在周）。
void showCourseDetailSheet(
  BuildContext context,
  Course course,
  Map<int, SectionTime> sectionTimes, {
  VoidCallback? onJumpToWeek,
}) {
  final color = Color(course.colorValue);
  final theme = Theme.of(context);
  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    course.name,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (course.teacher != null && course.teacher!.isNotEmpty)
              _DetailRow(
                icon: Icons.person_outline,
                label: '教师',
                value: course.teacher!,
              ),
            if (course.location != null && course.location!.isNotEmpty)
              _DetailRow(
                icon: Icons.room_outlined,
                label: '教室',
                value: course.location!,
              ),
            _DetailRow(
              icon: Icons.calendar_today_outlined,
              label: '时间',
              value: '周${_dayLabels[course.dayOfWeek - 1]} '
                  '第${course.startSection}-${course.endSection}节'
                  '${_formatSectionTime(course.startSection, course.endSection, sectionTimes)}',
            ),
            _DetailRow(
              icon: Icons.date_range_outlined,
              label: '周次',
              value: _formatWeeks(course.weeks),
            ),
            if (course.notes != null && course.notes!.isNotEmpty)
              _DetailRow(
                icon: Icons.notes_outlined,
                label: '备注',
                value: course.notes!,
              ),
            const SizedBox(height: 12),
            if (onJumpToWeek != null) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    onJumpToWeek();
                  },
                  icon: const Icon(Icons.today_outlined, size: 18),
                  label: const Text('跳到本周'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push('/course/edit', extra: course.id);
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑课程'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push('/course/edit', extra: 'copy:${course.id}');
                },
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('复制课程'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

String _formatWeeks(List<int> weeks) {
  if (weeks.isEmpty) return '无';
  final sorted = List<int>.from(weeks)..sort();
  final ranges = <String>[];
  var start = sorted.first;
  var end = sorted.first;
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i] == end + 1) {
      end = sorted[i];
    } else {
      ranges.add(start == end ? '$start' : '$start-$end');
      start = sorted[i];
      end = sorted[i];
    }
  }
  ranges.add(start == end ? '$start' : '$start-$end');
  return ranges.join(', ');
}

String _formatSectionTime(
    int startSection, int endSection, Map<int, SectionTime> sectionTimes) {
  final start = sectionTimes[startSection]?.startTime ?? '';
  final end = sectionTimes[endSection]?.endTime ?? '';
  if (start.isEmpty || end.isEmpty) return '';
  return ' ($start-$end)';
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.hintColor),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            child: Text(
              label,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}