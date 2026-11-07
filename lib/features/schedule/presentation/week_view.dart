import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:recess/core/constants/app_constants.dart';
import 'package:recess/core/models/course.dart';
import 'package:recess/core/utils/week_calculator.dart';
import 'package:recess/core/widgets/load_failed_view.dart';
import 'package:recess/features/schedule/domain/schedule_helpers.dart';
import 'package:recess/features/semester/application/semester_providers.dart';
import 'package:recess/features/settings/application/section_times_provider.dart';
import 'course_detail_sheet.dart';

/// 每节高度（px）。节次多到超出屏幕时网格区可纵向滚动。
const double _sectionHeight = 56.0;

/// 卡片与节格之间的留白。
const double _cardInset = 2.0;

/// 左侧时间轴宽度。
const double _timeAxisWidth = 36.0;

/// 表格底部在系统导航条之外额外留出的空白。
const double _bottomGap = 24.0;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(scheduleCoursesProvider);
    final sectionTimes = ref.watch(sectionTimesProvider);
    // 只取一次当前日期，避免多次 DateTime.now() 在午夜边界不一致。
    final now = DateTime.now();
    final todayWeekday = now.weekday; // 1..7

    // 节高随系统字号缩放（clamp 1.0–1.6）：大字号下自动加高避免挤压。
    final sectionHeight = _sectionHeight *
        (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(1.0, 1.6);

    // 学期开学日期，用于推算选中周每天的实际日期。
    final semesterAsync = ref.watch(activeSemesterProvider);
    final semester = semesterAsync.valueOrNull;
    final semesterStart = semester?.startDate;
    // 仅当查看的是当前周时，才在表头标示"今天"（避免查看历史/未来周时
    // 误标某一天的日期）。学期外没有可高亮的当前教学周。
    final currentWeek = semester != null ? teachingWeekOf(semester, now) : null;
    final isCurrentWeek = currentWeek != null && currentWeek == selectedWeek;

    return Column(
      children: [
        _DayHeaderRow(
          todayWeekday: todayWeekday,
          semesterStart: semesterStart,
          selectedWeek: selectedWeek,
          isCurrentWeek: isCurrentWeek,
        ),
        Expanded(
          // 当前学期（上游）失败时不能当作无课程：同样进入失败重试状态。
          child: semesterAsync.hasError && !semesterAsync.isLoading
              ? LoadFailedView(
                  title: '课表加载失败',
                  message: '课程数据没有读取出来，点击重试重新加载',
                  onRetry: () => _retryReload(ref),
                )
              : coursesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => LoadFailedView(
                    title: '课表加载失败',
                    message: '课程数据没有读取出来，点击重试重新加载',
                    onRetry: () => _retryReload(ref),
                  ),
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

                    final sectionCount = visibleSectionCount(
                      sectionTimes: sectionTimes,
                      courses: allCourses,
                    );
                    final totalHeight = sectionCount * sectionHeight;

                    return SingleChildScrollView(
                      key: const Key('week-view-vertical-scroll'),
                      scrollDirection: Axis.vertical,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + _bottomGap,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TimeAxis(
                            sectionCount: sectionCount,
                            sectionHeight: sectionHeight,
                            sectionTimes: sectionTimes,
                          ),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: List.generate(7, (i) {
                                final day = i + 1;
                                return Expanded(
                                  child: _DayColumn(
                                    sectionHeight: sectionHeight,
                                    courses: byDay[day]!,
                                    totalHeight: totalHeight,
                                    onTapCourse: (course) =>
                                        showCourseDetailSheet(
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

  /// 重试重新加载真正失败的数据源：课程流与当前学期（上游）一起失效，
  /// 不把上游失败当成无课程。不会切换学期或重置查看周。
  void _retryReload(WidgetRef ref) {
    ref.invalidate(activeSemesterProvider);
    ref.invalidate(scheduleCoursesProvider);
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
    // 跨月周与 WakeUp 一致只显示周一所在月，窄时间轴放不下 "7-8月"。
    final monthLabel = hasDates ? '${dates.first.month}月' : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: _timeAxisWidth,
            child: monthLabel != null
                ? Text(
                    monthLabel,
                    key: const Key('week-view-month-label'),
                    textAlign: TextAlign.center,
                    softWrap: false,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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
                      '周${AppConstants.weekdayLabels[i]}',
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
/// 节次号与起止时间分两级字号，未设时间的节次只显示节次号。
class _TimeAxis extends StatelessWidget {
  final int sectionCount;
  final double sectionHeight;
  final Map<int, SectionTime> sectionTimes;
  const _TimeAxis({
    required this.sectionCount,
    required this.sectionHeight,
    required this.sectionTimes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 36 宽的时间轴放不下 11sp 的 "08:00"，起止时间是全页唯一降到 10sp 的文字。
    final timeStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: 10,
      letterSpacing: -0.2,
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.15,
    );
    return SizedBox(
      key: const Key('week-view-time-axis'),
      width: _timeAxisWidth,
      height: sectionCount * sectionHeight,
      child: Column(
        children: List.generate(sectionCount, (i) {
          final section = i + 1;
          final sectionTime = sectionTimes[section];
          final startTime = sectionTime?.startTime ?? '';
          final endTime = sectionTime?.endTime ?? '';
          return SizedBox(
            height: sectionHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$section',
                  key: ValueKey('section-axis-$section'),
                  semanticsLabel: '第$section节',
                  softWrap: false,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                if (startTime.isNotEmpty)
                  Text(startTime, softWrap: false, style: timeStyle),
                if (endTime.isNotEmpty)
                  Text(endTime, softWrap: false, style: timeStyle),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// 单日列：按节次定位课程卡片，不画网格线。
class _DayColumn extends StatelessWidget {
  final List<Course> courses;
  final double sectionHeight;
  final double totalHeight;
  final void Function(Course) onTapCourse;
  final void Function(Course) onLongPressCourse;

  const _DayColumn({
    required this.courses,
    required this.sectionHeight,
    required this.totalHeight,
    required this.onTapCourse,
    required this.onLongPressCourse,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: totalHeight,
      child: Stack(
        children: courses.map((c) {
          final top = (c.startSection - 1) * sectionHeight + _cardInset;
          final height = (c.endSection - c.startSection + 1) * sectionHeight -
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
        }).toList(),
      ),
    );
  }
}

/// 课程卡片：课程色实色圆角色块，白字只写课名和“@教室”。
///
/// 教师与课程平台不上卡片，只在详情面板里显示；语义标签仍包含教师。
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
    final background = courseCardColor(
      Color(course.colorValue),
      theme.brightness,
    );
    final location = course.location?.trim() ?? '';

    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: _semanticLabel,
      hint: '点击查看详情，长按编辑',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 5, 4, 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final nameStyle = theme.textTheme.labelMedium!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                );
                // 按卡片可用高度能容纳的行数截断，字号跟随系统缩放。
                final lineHeight = MediaQuery.textScalerOf(context)
                        .scale(nameStyle.fontSize!) *
                    nameStyle.height!;
                final maxLines =
                    math.max(1, (constraints.maxHeight / lineHeight).floor());
                return Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: course.name),
                      if (location.isNotEmpty)
                        TextSpan(
                          text: '\n@$location',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  key: const Key('course-card-text'),
                  style: nameStyle,
                  maxLines: maxLines,
                  overflow: TextOverflow.clip,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String get _semanticLabel {
    final details = <String>[
      course.name,
      '周${AppConstants.weekdayLabels[course.dayOfWeek - 1]}',
      '第${course.startSection}到${course.endSection}节',
      if (course.location != null && course.location!.trim().isNotEmpty)
        course.location!.trim(),
      if (course.teacher != null && course.teacher!.trim().isNotEmpty)
        course.teacher!.trim(),
    ];
    return details.join('，');
  }
}

/// 色板使用已确认的主题色值；自定义颜色保留原来的白字可读性处理。
Color courseCardColor(Color base, Brightness brightness) {
  final value = base.toARGB32();
  if (AppConstants.coursePaletteIndex(value) != null) {
    return Color(AppConstants.courseDisplayColor(
      value,
      dark: brightness == Brightness.dark,
    ));
  }
  var hsl = HSLColor.fromColor(base);
  var color = base;
  while (_contrastWithWhite(color) < 3.0 && hsl.lightness > 0) {
    hsl = hsl.withLightness(math.max(0, hsl.lightness - 0.01));
    color = hsl.toColor();
  }
  if (brightness == Brightness.dark) {
    color = hsl.withLightness(hsl.lightness * 0.82).toColor();
  }
  return color;
}

double _contrastWithWhite(Color background) =>
    1.05 / (background.computeLuminance() + 0.05);

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
