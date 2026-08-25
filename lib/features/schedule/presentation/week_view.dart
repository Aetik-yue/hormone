import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/utils/week_calculator.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';

/// 每节高度（px）。16 节约 896px，超出屏幕时网格区可纵向滚动。
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
    // 只取一次当前日期，避免多次 DateTime.now() 在午夜边界不一致。
    final now = DateTime.now();
    final todayWeekday = now.weekday; // 1..7
    final maxSections = sectionTimes.length;

    // 学期开学日期，用于推算选中周每天的实际日期。
    final semesterStart =
        ref.watch(activeSemesterProvider).valueOrNull?.startDate;
    // 仅当查看的是当前周时，才高亮"今天"所在列（避免查看历史/未来周时
    // 误高亮某一天的日期）。currentWeek>0 防御开学前误判。
    final currentWeek =
        semesterStart != null ? computeCurrentWeek(semesterStart, now) : 0;
    final isCurrentWeek = currentWeek > 0 && currentWeek == selectedWeek;

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
            loading: () => const Center(child: CircularProgressIndicator()),
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
                key: const Key('week-view-vertical-scroll'),
                scrollDirection: Axis.vertical,
                physics: const AlwaysScrollableScrollPhysics(),
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
                              onTapCourse: (course) => _showCourseDetail(
                                  context, course, sectionTimes),
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

  void _showCourseDetail(
      BuildContext context, Course course, Map<int, SectionTime> sectionTimes) {
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
  String _formatSectionTime(
      int startSection, int endSection, Map<int, SectionTime> sectionTimes) {
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
    // 一次性算出选中周 7 天的日期，月份标签与各列日期共用同一份结果。
    final dates = semesterStart != null
        ? [
            for (var d = 1; d <= 7; d++)
              dateForWeekday(semesterStart!, selectedWeek, d),
          ]
        : <DateTime>[];
    final hasDates = dates.isNotEmpty;
    // 跨月时显示 "7-8月"，否则 "7月"。
    final monthLabel = hasDates
        ? (dates.first.month == dates.last.month
            ? '${dates.first.month}月'
            : '${dates.first.month}-${dates.last.month}月')
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
            final date = hasDates ? dates[i] : null;
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
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$section',
                        key: ValueKey('section-axis-$section'),
                        semanticsLabel: '第$section节',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.hintColor,
                          fontSize: 10,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (startTime.isNotEmpty) const SizedBox(height: 2),
                      if (startTime.isNotEmpty)
                        Text(
                          startTime,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.hintColor,
                            fontSize: 8.5,
                            height: 1,
                          ),
                        ),
                      if (endTime.isNotEmpty) const SizedBox(height: 1),
                      if (endTime.isNotEmpty)
                        Text(
                          endTime,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.hintColor,
                            fontSize: 8.5,
                            height: 1,
                          ),
                        ),
                    ],
                  ),
                ),
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
    final gridColor = theme.colorScheme.outlineVariant.withAlpha(
      theme.brightness == Brightness.dark ? 76 : 92,
    );
    final sectionCount = (totalHeight / _sectionHeight).round();
    return Container(
      height: totalHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isToday
            ? theme.colorScheme.primary.withAlpha(
                theme.brightness == Brightness.dark ? 24 : 15,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: gridColor, width: 0.6)),
      ),
      child: Stack(
        children: [
          // 课表网格是信息结构而不是装饰：横线对应节次，竖线对应星期。
          Positioned.fill(
            child: IgnorePointer(
              child: Column(
                children: List.generate(
                  sectionCount,
                  (_) => SizedBox(
                    height: _sectionHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: gridColor, width: 0.6),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ...courses.map((c) {
            final top = (c.startSection - 1) * _sectionHeight + _cardInset;
            final height =
                (c.endSection - c.startSection + 1) * _sectionHeight -
                    _cardInset * 2;
            return Positioned(
              key: ValueKey(c.id),
              top: top,
              left: _cardInset,
              right: _cardInset,
              height: height,
              child: CourseCard(
                key: ValueKey(c.id),
                course: c,
                onTap: () => onTapCourse(c),
                onLongPress: () => onLongPressCourse(c),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 课程卡片：用课程色时间轨建立识别，低饱和卡面承载文字。
///
/// 窄列优先把高度留给课程名；卡片足够高时再依次展示教室、教师。
class CourseCard extends StatelessWidget {
  final Course course;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const CourseCard({
    super.key,
    required this.course,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Color(course.colorValue);
    final surface = courseCardSurfaceColor(
      accent,
      theme.colorScheme,
      theme.brightness,
    );
    final foreground = courseCardForegroundColor(surface);
    final border = Color.alphaBlend(
      accent.withAlpha(theme.brightness == Brightness.dark ? 138 : 112),
      surface,
    );

    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: _semanticLabel,
      hint: '点击查看详情，长按编辑',
      child: Material(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border, width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          overlayColor: WidgetStatePropertyAll(accent.withAlpha(28)),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactWidth = constraints.maxWidth < 56;
              final showLocation = constraints.maxHeight >= 64 &&
                  course.location != null &&
                  course.location!.trim().isNotEmpty;
              final showTeacher = constraints.maxHeight >= 92 &&
                  course.teacher != null &&
                  course.teacher!.trim().isNotEmpty;
              final fontSize = compactWidth ? 10.5 : 11.5;
              final detailHeight =
                  (showLocation ? 14.0 : 0) + (showTeacher ? 13.0 : 0);
              final verticalPadding = constraints.maxHeight < 56 ? 3.0 : 5.0;
              final titleHeight =
                  constraints.maxHeight - verticalPadding * 2 - detailHeight;
              final titleLines =
                  (titleHeight / (fontSize * 1.08)).floor().clamp(1, 4);

              return Stack(
                children: [
                  Positioned(
                    key: const Key('course-card-color-rail'),
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: compactWidth ? 3 : 4,
                    child: ColoredBox(color: accent),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compactWidth ? 6 : 8,
                        verticalPadding,
                        compactWidth ? 3 : 5,
                        verticalPadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                course.name,
                                key: const Key('course-card-name'),
                                maxLines: titleLines,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: fontSize,
                                  height: 1.08,
                                  letterSpacing: compactWidth ? -0.35 : -0.15,
                                  fontWeight: FontWeight.w700,
                                  color: foreground,
                                ),
                              ),
                            ),
                          ),
                          if (showLocation)
                            _CourseCardMeta(
                              key: const Key('course-card-location'),
                              value: course.location!.trim(),
                              color: foreground,
                              fontSize: compactWidth ? 9 : 9.5,
                            ),
                          if (showTeacher)
                            _CourseCardMeta(
                              key: const Key('course-card-teacher'),
                              value: course.teacher!.trim(),
                              color: foreground,
                              fontSize: compactWidth ? 8.5 : 9,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String get _semanticLabel {
    final details = <String>[
      course.name,
      '周${WeekView._dayLabels[course.dayOfWeek - 1]}',
      '第${course.startSection}到${course.endSection}节',
      if (course.location != null && course.location!.trim().isNotEmpty)
        course.location!.trim(),
      if (course.teacher != null && course.teacher!.trim().isNotEmpty)
        course.teacher!.trim(),
    ];
    return details.join('，');
  }
}

class _CourseCardMeta extends StatelessWidget {
  final String value;
  final Color color;
  final double fontSize;

  const _CourseCardMeta({
    super.key,
    required this.value,
    required this.color,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        height: 1.15,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

/// 将课程色混入主题表面，降低一屏七列课程块的色彩噪声。
Color courseCardSurfaceColor(
  Color accent,
  ColorScheme colorScheme,
  Brightness brightness,
) {
  final alpha = brightness == Brightness.dark ? 66 : 42;
  return Color.alphaBlend(accent.withAlpha(alpha), colorScheme.surface);
}

/// 在深色墨水和白色之间选择对比度更高的课程卡片前景色。
Color courseCardForegroundColor(Color background) {
  const darkInk = Color(0xFF101522);
  const lightInk = Colors.white;
  final backgroundLuminance = background.computeLuminance();

  double contrast(Color foreground) {
    final foregroundLuminance = foreground.computeLuminance();
    final lighter = foregroundLuminance > backgroundLuminance
        ? foregroundLuminance
        : backgroundLuminance;
    final darker = foregroundLuminance > backgroundLuminance
        ? backgroundLuminance
        : foregroundLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

  return contrast(darkInk) >= contrast(lightInk) ? darkInk : lightInk;
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
            style:
                theme.textTheme.titleMedium?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 4),
          Text(
            hasAnyCourses ? '当前周次没有安排课程\n试试切换到其他周次' : '从教务系统导入或手动添加课程',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            textAlign: TextAlign.center,
          ),
          if (!hasAnyCourses &&
              (onImport != null || onWebViewImport != null)) ...[
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
