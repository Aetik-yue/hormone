import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:recess/core/constants/app_constants.dart';
import 'package:recess/core/models/course.dart';
import 'package:recess/core/utils/week_calculator.dart';
import 'package:recess/features/course/domain/course_clock.dart';
import 'package:recess/features/semester/application/semester_mutations.dart';
import 'package:recess/features/schedule/domain/schedule_helpers.dart';
import 'package:recess/features/settings/application/section_times_provider.dart';
import '../application/schedule_providers.dart';
import '../../semester/application/semester_providers.dart';
import 'course_detail_sheet.dart';
import 'course_search_delegate.dart';
import 'week_view.dart';

/// 课程表主页：日期 + 查看周标题（点开为周操作菜单）+ 可左右滑动的周视图。
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key, this.now});

  final DateTime Function()? now;

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  /// 周次分页控制器（页索引 = 周次 - 1）。
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController =
        PageController(initialPage: ref.read(selectedWeekProvider) - 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semester = ref.watch(activeSemesterProvider).valueOrNull;
    final totalWeeks = semester?.totalWeeks ?? 18;
    final now = (widget.now ?? DateTime.now)();
    // 开学前或学期已结束时没有可翻到的「本周」，不显示后缀与「回到本周」。
    final currentWeek = semester == null ? null : teachingWeekOf(semester, now);
    final theme = Theme.of(context);
    // 顶栏高度随系统字号缩放，避免两行标题在大字号下被挤压。
    final textScale =
        (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(1.0, 1.6);

    // 外部周次变化（异步首屏定位、深链跳转等）时对齐分页位置。
    // 每次 build 后也兜底同步，覆盖 Provider 在 PageView 挂载前完成初始化的竞态。
    ref.listen<int>(selectedWeekProvider, (prev, next) {
      _schedulePageSync(next);
    });
    _schedulePageSync(ref.read(selectedWeekProvider));

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56 * textScale,
        titleSpacing: 8,
        title: Consumer(
          builder: (context, ref, child) {
            final selectedWeek = ref.watch(selectedWeekProvider);
            final isViewingCurrentWeek =
                currentWeek == null || currentWeek == selectedWeek;
            return PopupMenuButton<_WeekMenuAction>(
              key: const Key('schedule-week-menu'),
              tooltip: '周操作',
              position: PopupMenuPosition.under,
              offset: const Offset(0, 4),
              onSelected: (action) {
                switch (action) {
                  case _WeekMenuAction.jump:
                    _showWeekPicker(
                      title: '跳转到第几周',
                      totalWeeks: totalWeeks,
                      selected: selectedWeek,
                      onPick: (week) => _animateToWeek(week, totalWeeks),
                    );
                  case _WeekMenuAction.backToCurrent:
                    if (currentWeek != null) {
                      _animateToWeek(currentWeek, totalWeeks);
                    }
                  case _WeekMenuAction.setCurrent:
                    _showWeekPicker(
                      title: '修改当前周',
                      totalWeeks: totalWeeks,
                      selected: currentWeek ?? selectedWeek,
                      onPick: _setCurrentWeek,
                    );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _WeekMenuAction.jump,
                  child: _ScheduleMenuItem(
                    icon: Icons.calendar_view_month_outlined,
                    label: '跳转到第几周',
                  ),
                ),
                if (!isViewingCurrentWeek)
                  const PopupMenuItem(
                    value: _WeekMenuAction.backToCurrent,
                    child: _ScheduleMenuItem(
                      icon: Icons.today_outlined,
                      label: '回到本周',
                    ),
                  ),
                const PopupMenuItem(
                  value: _WeekMenuAction.setCurrent,
                  child: _ScheduleMenuItem(
                    icon: Icons.edit_calendar_outlined,
                    label: '修改当前周',
                  ),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${now.year}/${now.month}/${now.day}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      isViewingCurrentWeek
                          ? '第 $selectedWeek 周'
                          : '第 $selectedWeek 周   当前为第 $currentWeek 周',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加课程',
            onPressed: () => context.push('/course/edit'),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索课程',
            onPressed: () => _openCourseSearch(context, ref),
          ),
          PopupMenuButton<_ScheduleMenuAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onSelected: (action) {
              switch (action) {
                case _ScheduleMenuAction.today:
                  _showTodaySheet(context, ref);
                case _ScheduleMenuAction.importGuide:
                  context.push('/import/guide');
                case _ScheduleMenuAction.settings:
                  context.push('/settings');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ScheduleMenuAction.today,
                child: _ScheduleMenuItem(
                  icon: Icons.today_outlined,
                  label: '今日课程',
                ),
              ),
              PopupMenuItem(
                value: _ScheduleMenuAction.importGuide,
                child: _ScheduleMenuItem(
                  icon: Icons.help_outline_rounded,
                  label: '课程抓取说明',
                ),
              ),
              PopupMenuItem(
                value: _ScheduleMenuAction.settings,
                child: _ScheduleMenuItem(
                  icon: Icons.settings_outlined,
                  label: '设置',
                ),
              ),
            ],
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: totalWeeks,
        allowImplicitScrolling: true,
        physics: const _SchedulePagePhysics(
          parent: BouncingScrollPhysics(),
        ),
        onPageChanged: (index) {
          final week = index + 1;
          if (week != ref.read(selectedWeekProvider)) {
            ref
                .read(selectedWeekProvider.notifier)
                .goTo(week, totalWeeks: totalWeeks);
          }
        },
        itemBuilder: (context, index) {
          final week = index + 1;
          // 用背景色遮罩淡化页面，避免 Opacity 给整页开离屏图层。
          // WeekView 作为 child 复用，不随手势每帧重建。
          return AnimatedBuilder(
            animation: _pageController,
            child: WeekView(
              key: ValueKey(week),
              selectedWeek: week,
              onImport: () => context.push('/import'),
              onWebViewImport: () => context.push('/import/webview'),
            ),
            builder: (context, child) {
              var currentPage = index.toDouble();
              if (_pageController.hasClients &&
                  _pageController.position.hasContentDimensions) {
                currentPage = _pageController.page ?? currentPage;
              }
              final distance =
                  (currentPage - index).abs().clamp(0.0, 1.0).toDouble();
              // 保持祖先结构不变，避免拖动起落时重建周视图并丢失滚动位置。
              return Transform.scale(
                scale: 1 - distance * 0.012,
                alignment: Alignment.center,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child!,
                    if (distance > 0)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Theme.of(context)
                                .scaffoldBackgroundColor
                                .withValues(alpha: distance * 0.08),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// 把选中的周写成激活学期的手动当前周，翻到该周并提示。
  Future<void> _setCurrentWeek(int week) async {
    final semester = ref.read(activeSemesterProvider).valueOrNull;
    if (semester == null) return;
    try {
      await ref
          .read(semesterMutationsProvider)
          .save(semester.copyWith(currentWeekOverride: week));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
      return;
    }
    if (!mounted) return;
    _animateToWeek(week, semester.totalWeeks);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('当前周已改为第 $week 周')));
  }

  /// 选周网格底部弹层，「跳转到第几周」与「修改当前周」共用。
  void _showWeekPicker({
    required String title,
    required int totalWeeks,
    required int selected,
    required ValueChanged<int> onPick,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              const Divider(height: 1),
              SizedBox(
                height: 300,
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.5,
                  ),
                  itemCount: totalWeeks,
                  itemBuilder: (context, i) {
                    final week = i + 1;
                    final isSelected = week == selected;
                    return InkWell(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onPick(week);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.dividerColor,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$week',
                          style: TextStyle(
                            color: isSelected
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _schedulePageSync(int week) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      final target = week - 1;
      if ((_pageController.page ?? target).round() != target) {
        _pageController.jumpToPage(target);
      }
    });
  }

  /// 所有显式跳周都使用同一套动画；距离越远动画略长，但设置上限避免拖沓。
  /// 系统要求减少动态效果时直接跳转，尊重无障碍偏好。
  void _animateToWeek(int week, int totalWeeks) {
    final safeWeek = week.clamp(1, totalWeeks);
    final targetPage = safeWeek - 1;
    if (!_pageController.hasClients ||
        MediaQuery.of(context).disableAnimations) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetPage);
      } else {
        ref
            .read(selectedWeekProvider.notifier)
            .goTo(safeWeek, totalWeeks: totalWeeks);
      }
      return;
    }

    final currentPage = _pageController.page ?? (safeWeek - 1).toDouble();
    final distance =
        (currentPage - targetPage).abs().ceil().clamp(1, 4).toInt();
    _pageController.animateToPage(
      targetPage,
      duration: Duration(milliseconds: 220 + distance * 45),
      curve: Curves.easeOutQuint,
    );
  }

  /// 「今日课程」时间线底部弹层。
  Future<void> _showTodaySheet(BuildContext context, WidgetRef ref) async {
    final semester = ref.read(activeSemesterProvider).value;
    final courses =
        ref.read(scheduleCoursesProvider).value ?? const <Course>[];
    final sectionTimes = ref.read(sectionTimesProvider);
    final now = (widget.now ?? DateTime.now)();
    final currentWeek = semester == null ? null : teachingWeekOf(semester, now);
    final beforeStart = semester == null || currentWeekOf(semester, now) < 1;
    final slots = currentWeek == null
        ? const <TodayCourseSlot>[]
        : todayCourseSlots(
            courses: courses,
            currentWeek: currentWeek,
            now: now,
            sectionTimes: sectionTimes,
          );

    final theme = Theme.of(context);
    final todayLabel = AppConstants.weekdayLabels[now.weekday - 1];
    final dateLabel = '${now.month}月${now.day}日';

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Row(
                  children: [
                    Text('今日课程', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    Text(
                      currentWeek != null
                          ? '第 $currentWeek 周 · 周$todayLabel $dateLabel'
                          : (beforeStart ? '尚未开学' : '学期已结束'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (slots.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      currentWeek != null
                          ? '今天没有课程'
                          : (beforeStart ? '开学后再来看看' : '本学期课程已结束'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: slots.length,
                    itemBuilder: (context, i) {
                      final slot = slots[i];
                      final c = slot.course;
                      return ListTile(
                        leading: SizedBox(
                          width: 64,
                          child: Text(
                            _slotClock(c, sectionTimes),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        title: Text(c.name),
                        subtitle: Text(
                          [
                            if (c.location != null && c.location!.isNotEmpty)
                              c.location!,
                            if (c.teacher != null && c.teacher!.isNotEmpty)
                              c.teacher!,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: _StatusChip(status: slot.status),
                        onTap: () => showCourseDetailSheet(
                            context, c, sectionTimes),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _slotClock(Course c, Map<int, SectionTime> sectionTimes) {
    final clock = CourseClock(c, sectionTimes);
    final start = clock.startTime;
    final end = clock.endTime;
    if (start != null && end != null) return '$start-$end';
    return '第${c.startSection}-${c.endSection}节';
  }

  /// 弹出课程搜索，选中后展示详情并支持跳到该周。
  Future<void> _openCourseSearch(BuildContext context, WidgetRef ref) async {
    final totalWeeks =
        ref.read(activeSemesterProvider).valueOrNull?.totalWeeks ?? 18;
    final course = await showSearch<Course?>(
      context: context,
      delegate: CourseSearchDelegate(ref),
    );
    if (!mounted || course == null) return;
    final sectionTimes = ref.read(sectionTimesProvider);
    showCourseDetailSheet(
      context,
      course,
      sectionTimes,
      onJumpToWeek: () {
        if (course.weeks.isNotEmpty) {
          _animateToWeek(course.weeks.first, totalWeeks);
        }
      },
    );
  }
}

/// 更轻、更快收敛的分页弹簧，并在 Android 上保留自然的边界回弹。
class _SchedulePagePhysics extends PageScrollPhysics {
  const _SchedulePagePhysics({super.parent});

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 0.82,
        stiffness: 240,
        damping: 28,
      );

  @override
  _SchedulePagePhysics applyTo(ScrollPhysics? ancestor) {
    return _SchedulePagePhysics(parent: buildParent(ancestor));
  }
}

enum _WeekMenuAction { jump, backToCurrent, setCurrent }

enum _ScheduleMenuAction { today, importGuide, settings }

class _ScheduleMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ScheduleMenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

/// 今日课程时间线的状态标签。
class _StatusChip extends StatelessWidget {
  final CourseStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, background) = switch (status) {
      CourseStatus.ongoing => (
          '进行中',
          theme.colorScheme.primary,
          theme.colorScheme.primary.withAlpha((0.14 * 255).round()),
        ),
      CourseStatus.upcoming => (
          '未开始',
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.surfaceContainerHighest,
        ),
      CourseStatus.done => (
          '已结束',
          theme.colorScheme.outline,
          theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
