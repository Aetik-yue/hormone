import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/utils/week_calculator.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';

/// 每节高度（px）。12 节约 672px，超出屏幕时整体可纵向滚动。
const double _sectionHeight = 56.0;
/// 卡片与节格之间的留白。
const double _cardInset = 4.0;
/// 左侧时间轴宽度。
const double _timeAxisWidth = 48.0;

/// 周视图课程表：左侧节次时间轴 + 右侧 7 天列，课程卡片按节次定位。
/// 点击课程卡片弹出详情，长按进入编辑。
class WeekView extends ConsumerWidget {
  final int selectedWeek;
  final VoidCallback? onImport;
  final VoidCallback? onWebViewImport;

  const WeekView({
    super.key,
    required this.selectedWeek,
    this.onImport,
    this.onWebViewImport,
  });

  static const _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(scheduleCoursesProvider);
    final sectionTimes = ref.watch(sectionTimesProvider);
    final todayWeekday = DateTime.now().weekday; // 1..7
    final maxSections = sectionTimes.length;

    // 学期开学日期，用于推算选中周每天的实际日期。
    final semesterStart =
        ref.watch(activeSemesterProvider).valueOrNull?.startDate;
    // 仅当查看的是当前周时，才高亮"今天"所在列（避免查看历史/未来周时
    // 误高亮某一天的日期）。
    final isCurrentWeek = semesterStart != null &&
        computeCurrentWeek(semesterStart, DateTime.now()) == selectedWeek;

    return Column(
      children: [
        _DayHeaderRow(
          todayWeekday: todayWeekday,
          semesterStart: semesterStart,
          selectedWeek: selectedWeek,
          isCurrentWeek: isCurrentWeek,
        ),
        Expanded(
          child: coursesAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败：$e')),
            data: (allCourses) {
              final weekCourses = allCourses
                  .where((c) => courseOnWeek(c.weeks, selectedWeek))
                  .toList();

              if (weekCourses.isEmpty) {
                return _EmptyWeekHint(
                  hasAnyCourses: allCourses.isNotEmpty,
                  onImport: onImport,
                  onWebViewImport: onWebViewImport,
                );
              }

              final byDay = <int, List<Course>>{
                for (var d = 1; d <= 7; d++) d: [],
              };
              for (final c in weekCourses) {
                byDay[c.dayOfWeek]?.add(c);
              }

              final totalHeight = maxSections * _sectionHeight;

              return SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TimeAxis(
                      totalHeight: totalHeight,
                      sectionTimes: sectionTimes,
                    ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(7, (i) {
                          final day = i + 1;
                          return Expanded(
                            child: _DayColumn(
                              day: day,
                              isToday: isCurrentWeek && day == todayWeekday,
                              courses: byDay[day]!,
                              totalHeight: totalHeight,
                              onTapCourse: (course) =>
                                  _showCourseDetail(context, course, sectionTimes),
                              onLongPressCourse: (course) => context.push(
                                '/course/edit',
                                extra: course.id,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCourseDetail(BuildContext context, Course course, Map<int, SectionTime> sectionTimes) {
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
                value:
                    '周${_dayLabels[course.dayOfWeek - 1]} 第${course.startSection}-${course.endSection}节'
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
    // 压缩连续周次为范围表示，如 1-16
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

  /// 返回节次对应的时钟时间范围，如 " (08:00-08:45)"。
  String _formatSectionTime(int startSection, int endSection, Map<int, SectionTime> sectionTimes) {
    final start = sectionTimes[startSection]?.startTime ?? '';
    final end = sectionTimes[endSection]?.endTime ?? '';
    if (start.isEmpty || end.isEmpty) return '';
    return ' ($start-$end)';
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
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
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

/// 顶部星期表头：左上角显示月份，每列星期下方显示日期，今天加粗并着主题色。
class _DayHeaderRow extends StatelessWidget {
  final int todayWeekday;
  final DateTime? semesterStart;
  final int selectedWeek;
  final bool isCurrentWeek;
  const _DayHeaderRow({
    required this.todayWeekday,
    required this.semesterStart,
    required this.selectedWeek,
    required this.isCurrentWeek,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasStart = semesterStart != null;
    // 选中周周一与周日，用于左上角月份与各列日期。
    final firstDate =
        hasStart ? dateForWeekday(semesterStart!, selectedWeek, 1) : null;
    final lastDate =
        hasStart ? dateForWeekday(semesterStart!, selectedWeek, 7) : null;
    // 跨月时显示 "7-8月"，否则 "7月"。
    final monthLabel = firstDate != null && lastDate != null
        ? (firstDate.month == lastDate.month
            ? '${firstDate.month}月'
            : '${firstDate.month}-${lastDate.month}月')
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _timeAxisWidth,
            child: monthLabel != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Text(
                      monthLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.hintColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : null,
          ),
          ...List.generate(7, (i) {
            final day = i + 1;
            final isToday = isCurrentWeek && day == todayWeekday;
            final date =
                hasStart ? dateForWeekday(semesterStart!, selectedWeek, day) : null;
            return Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '周${WeekView._dayLabels[i]}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight:
                            isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday
                            ? theme.colorScheme.primary
                            : theme.hintColor,
                      ),
                    ),
                    if (date != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        '${date.day}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          fontWeight:
                              isToday ? FontWeight.bold : FontWeight.normal,
                          color: isToday
                              ? theme.colorScheme.primary
                              : theme.hintColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 左侧节次 + 该节起止时间（上下排列，使用自定义时间表）。
class _TimeAxis extends StatelessWidget {
  final double totalHeight;
  final Map<int, SectionTime> sectionTimes;
  const _TimeAxis({
    required this.totalHeight,
    required this.sectionTimes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = sectionTimes.length;
    return SizedBox(
      width: _timeAxisWidth,
      height: totalHeight,
      child: Stack(
        children: List.generate(count, (i) {
          final section = i + 1;
          final sectionTime = sectionTimes[section];
          final startTime = sectionTime?.startTime ?? '';
          final endTime = sectionTime?.endTime ?? '';
          return Positioned(
            top: i * _sectionHeight,
            left: 0,
            right: 0,
            height: _sectionHeight,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$section',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                  if (startTime.isNotEmpty)
                    Text(
                      startTime,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.hintColor,
                        fontSize: 9,
                      ),
                    ),
                  if (endTime.isNotEmpty)
                    Text(
                      endTime,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.hintColor,
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 单日列：按节次定位课程卡片，今天列背景微高亮。
class _DayColumn extends StatelessWidget {
  final int day;
  final bool isToday;
  final List<Course> courses;
  final double totalHeight;
  final void Function(Course) onTapCourse;
  final void Function(Course) onLongPressCourse;

  const _DayColumn({
    required this.day,
    required this.isToday,
    required this.courses,
    required this.totalHeight,
    required this.onTapCourse,
    required this.onLongPressCourse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: totalHeight,
      decoration: isToday
          ? BoxDecoration(
              color: theme.colorScheme.primary
                  .withAlpha((0.06 * 255).round()),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Stack(
        children: courses.map((c) {
          final top =
              (c.startSection - 1) * _sectionHeight + _cardInset;
          final height = (c.endSection - c.startSection + 1) * _sectionHeight -
              _cardInset * 2;
          return Positioned(
            key: ValueKey(c.id),
            top: top,
            left: _cardInset,
            right: _cardInset,
            height: height,
            child: _CourseCard(
              key: ValueKey(c.id),
              course: c,
              onTap: () => onTapCourse(c),
              onLongPress: () => onLongPressCourse(c),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 课程卡片：彩色底 + 白/深色字，课程名最多两行，附教室。
class _CourseCard extends StatelessWidget {
  final Course course;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _CourseCard({
    super.key,
    required this.course,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(course.colorValue);
    final fg = ThemeData.estimateBrightnessForColor(color) ==
            Brightness.light
        ? Colors.black87
        : Colors.white;

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                course.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              if (course.location != null &&
                  course.location!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  course.location!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: fg.withAlpha((0.78 * 255).round()),
                  ),
                ),
              ],
              if (course.teacher != null &&
                  course.teacher!.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  course.teacher!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    color: fg.withAlpha((0.65 * 255).round()),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 280.ms)
        .slideY(begin: 0.08, end: 0, duration: 280.ms, curve: Curves.easeOut);
  }
}

/// 无课程时的友好空状态。区分"无任何课程"和"本周无课"。
class _EmptyWeekHint extends StatelessWidget {
  final bool hasAnyCourses;
  final VoidCallback? onImport;
  final VoidCallback? onWebViewImport;
  const _EmptyWeekHint({
    required this.hasAnyCourses,
    this.onImport,
    this.onWebViewImport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_available_outlined,
              size: 56, color: theme.hintColor),
          const SizedBox(height: 12),
          Text(
            hasAnyCourses ? '本周暂无课程' : '尚未导入课程',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 4),
          Text(
            hasAnyCourses
                ? '当前周次没有安排课程\n试试切换到其他周次'
                : '从教务系统导入或手动添加课程',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.hintColor),
            textAlign: TextAlign.center,
          ),
          if (!hasAnyCourses && (onImport != null || onWebViewImport != null)) ...[
            const SizedBox(height: 16),
            if (onWebViewImport != null)
              FilledButton.icon(
                onPressed: onWebViewImport,
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('从教务导入'),
              ),
            if (onWebViewImport != null && onImport != null)
              const SizedBox(height: 8),
            if (onImport != null)
              OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('导入课表'),
              ),
          ],
        ],
      ),
    );
  }
}
