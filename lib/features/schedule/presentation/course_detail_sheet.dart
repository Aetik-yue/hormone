import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:recess/core/constants/app_constants.dart';
import 'package:recess/core/models/course.dart';
import 'package:recess/core/models/course_platform.dart';
import 'package:recess/features/course/application/course_platforms_provider.dart';
import 'package:recess/features/course/domain/course_clock.dart';
import 'package:recess/features/course/presentation/course_platform_display.dart';
import 'package:recess/features/settings/application/section_times_provider.dart';

/// 弹出课程详情底部弹层（课程表点击与搜索结果共用）。
///
/// [onJumpToWeek] 非空时额外显示「跳到本周」按钮（搜索场景跳转到该课所在周）。
void showCourseDetailSheet(
  BuildContext context,
  Course course,
  Map<int, SectionTime> sectionTimes, {
  VoidCallback? onJumpToWeek,
}) {
  final theme = Theme.of(context);
  final color = Color(AppConstants.courseDisplayColor(
    course.colorValue,
    dark: theme.brightness == Brightness.dark,
  ));
  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      // 平台条目较多时面板内容可滚动，避免超出弹层高度。
      return _SheetMessenger(child: SingleChildScrollView(
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
              value: '周${AppConstants.weekdayLabels[course.dayOfWeek - 1]} '
                  '第${course.startSection}-${course.endSection}节'
                  '${_formatCourseTime(course, sectionTimes)}',
            ),
            _DetailRow(
              icon: Icons.date_range_outlined,
              label: '周次',
              value: _formatWeeks(course.weeks),
            ),
            _PlatformSection(course: course),
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
      ));
    },
  );
}

/// 让面板里的 SnackBar 显示在弹层上方。
///
/// 根 ScaffoldMessenger 会把 SnackBar 放进下层页面的 Scaffold，被弹层挡住；
/// 这里给弹层单独一个 ScaffoldMessenger 和一个铺满弹层、不接收触摸的透明
/// Scaffold，弹层仍按内容高度布局。
class _SheetMessenger extends StatelessWidget {
  final Widget child;
  const _SheetMessenger({required this.child});

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Stack(
        children: [
          child,
          const Positioned.fill(
            child: IgnorePointer(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
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

String _formatCourseTime(Course course, Map<int, SectionTime> sectionTimes) {
  final clock = CourseClock(course, sectionTimes);
  final start = clock.startTime ?? '';
  final end = clock.endTime ?? '';
  if (start.isEmpty || end.isEmpty) return '';
  return ' ($start-$end)';
}

/// 「课程平台」区块，只负责显示；增删改在课程编辑页里做。
class _PlatformSection extends ConsumerWidget {
  final Course course;
  const _PlatformSection({required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final platforms = ref
            .watch(coursePlatformsProvider(
              (semesterId: course.semesterId, courseName: course.name),
            ))
            .valueOrNull ??
        const <CoursePlatform>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.apps_outlined, size: 18, color: theme.hintColor),
              const SizedBox(width: 10),
              Text(
                '课程平台',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
          if (platforms.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 6),
              child: Text(
                '还没有填写，可在“编辑课程”里添加',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final platform in platforms)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 18),
                visualDensity: VisualDensity.compact,
                leading: Icon(coursePlatformIcon(platform.purpose)),
                title: Text(coursePlatformTitle(platform)),
                subtitle: platform.url == null
                    ? null
                    : Text(
                        platform.url!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: platform.url == null
                    ? null
                    : const Icon(Icons.open_in_new, size: 18),
                onTap: platform.url == null
                    ? null
                    : () => _open(context, platform.url!),
                onLongPress: platform.url == null
                    ? null
                    : () => _copy(context, platform.url!),
              ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!isAllowedPlatformUrl(url)) {
      messenger.showSnackBar(const SnackBar(content: Text('链接协议不允许打开')));
      return;
    }
    final uri = Uri.tryParse(url);
    var opened = false;
    try {
      opened = uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text('无法打开链接：$url')));
    }
  }

  Future<void> _copy(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(const SnackBar(content: Text('已复制链接')));
  }
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
