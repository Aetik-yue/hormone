import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/core/utils/week_calculator.dart';
import 'package:hormone/data/providers/database_providers.dart';
import 'package:hormone/features/schedule/domain/schedule_helpers.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';
import '../application/schedule_providers.dart';
import '../../semester/application/semester_providers.dart';
import 'course_detail_sheet.dart';
import 'course_search_delegate.dart';
import 'week_view.dart';

/// 课程表主页：学期选择 + 周选择器 + 周视图时间轴。
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

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
    final selectedWeek = ref.watch(selectedWeekProvider);
    final activeSemester = ref.watch(activeSemesterProvider);

    final semesterName =
        activeSemester.whenOrNull(data: (s) => s?.name) ?? '未设置学期';
    final totalWeeks =
        activeSemester.whenOrNull(data: (s) => s?.totalWeeks) ?? 18;

    final computedWeek = activeSemester.whenOrNull(
      data: (s) =>
          s == null ? null : computeCurrentWeek(s.startDate, DateTime.now()),
    );
    final isCurrentWeek = computedWeek != null && computedWeek == selectedWeek;

    // 外部周次变化（异步首屏定位、切学期、深链跳转等）时对齐分页位置。
    // 每次 build 后也兜底同步，覆盖 Provider 在 PageView 挂载前完成初始化的竞态。
    ref.listen<int>(selectedWeekProvider, (prev, next) {
      _schedulePageSync(next);
    });
    _schedulePageSync(selectedWeek);

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => _showSemesterPicker(context, ref),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    semesterName,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: '课程抓取说明',
            onPressed: () => context.push('/import/guide'),
          ),
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: '今日课程',
            onPressed: () => _showTodaySheet(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索课程',
            onPressed: () => _openCourseSearch(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          _WeekSelector(
            selectedWeek: selectedWeek,
            totalWeeks: totalWeeks,
            isCurrentWeek: isCurrentWeek,
            currentWeek: computedWeek ?? 1,
            onPrev: () {
              _animateToWeek(selectedWeek - 1, totalWeeks);
            },
            onNext: () {
              _animateToWeek(selectedWeek + 1, totalWeeks);
            },
            onJumpToWeek: (week) {
              _animateToWeek(week, totalWeeks);
            },
          ),
          _WeekProgressIndicator(
            controller: _pageController,
            selectedWeek: selectedWeek,
            totalWeeks: totalWeeks,
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: totalWeeks,
              allowImplicitScrolling: true,
              physics: const _SchedulePagePhysics(
                parent: BouncingScrollPhysics(),
              ),
              onPageChanged: (index) {
                final week = index + 1;
                if (week != selectedWeek) {
                  ref
                      .read(selectedWeekProvider.notifier)
                      .goTo(week, totalWeeks: totalWeeks);
                }
              },
              itemBuilder: (context, index) {
                final week = index + 1;
                final page = RepaintBoundary(
                  child: WeekView(
                    key: ValueKey(week),
                    selectedWeek: week,
                    onImport: () => context.push('/import'),
                    onWebViewImport: () => context.push('/import/webview'),
                  ),
                );
                // 只让轻量的合成层随手势变化，WeekView 本身作为 child 不会
                // 每帧重建；轻微缩放与透明度差形成更自然的前后页交接。
                return AnimatedBuilder(
                  animation: _pageController,
                  child: page,
                  builder: (context, child) {
                    var currentPage = index.toDouble();
                    if (_pageController.hasClients &&
                        _pageController.position.hasContentDimensions) {
                      currentPage = _pageController.page ?? currentPage;
                    }
                    final distance =
                        (currentPage - index).abs().clamp(0.0, 1.0).toDouble();
                    return Transform.scale(
                      scale: 1 - distance * 0.012,
                      alignment: Alignment.center,
                      child: Opacity(
                        opacity: 1 - distance * 0.08,
                        child: child,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/course/edit'),
        tooltip: '添加课程',
        child: const Icon(Icons.add),
      ),
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
    final now = DateTime.now();
    final currentWeek = semester == null
        ? 0
        : semester.currentWeekOverride ??
            computeCurrentWeek(semester.startDate, now);
    final slots = todayCourseSlots(
      courses: courses,
      currentWeek: currentWeek,
      now: now,
      sectionTimes: sectionTimes,
    );

    final theme = Theme.of(context);
    final todayLabel = _dayLabels[now.weekday - 1];
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
                      currentWeek >= 1 ? '第 $currentWeek 周 · 周$todayLabel $dateLabel' : '尚未开学',
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
                      currentWeek >= 1 ? '今天没有课程' : '开学后再来看看',
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
    final start = c.startTime ?? sectionTimes[c.startSection]?.startTime;
    final end = c.endTime ?? sectionTimes[c.endSection]?.endTime;
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

  void _showSemesterPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final semestersAsync = ref.watch(semestersProvider);
            final active = ref.watch(activeSemesterProvider).value;
            final theme = Theme.of(context);

            return semestersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('加载失败：$e'),
              ),
              data: (semesters) {
                return SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Text('切换学期', style: theme.textTheme.titleMedium),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                context.push('/semester');
                              },
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('管理'),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ...semesters.map((s) {
                        final isActive = s.id == active?.id;
                        return ListTile(
                          leading: Icon(
                            isActive
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.hintColor,
                          ),
                          title: Text(s.name),
                          subtitle: Text('${s.totalWeeks} 周'),
                          trailing: isActive
                              ? Chip(
                                  label: const Text('当前'),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: theme.colorScheme.primary
                                      .withAlpha((0.12 * 255).round()),
                                )
                              : null,
                          onTap: isActive
                              ? null
                              : () async {
                                  final repo =
                                      ref.read(semesterRepositoryProvider);
                                  await repo.setActive(s.id);
                                  // scheduleCoursesProvider 内部 watch 了
                                  // activeSemesterProvider，失效会自动传播。
                                  ref.invalidate(activeSemesterProvider);
                                  // 切换学期后重置到当前周
                                  ref.read(selectedWeekProvider.notifier).goTo(
                                      computeCurrentWeek(
                                          s.startDate, DateTime.now()),
                                      totalWeeks: s.totalWeeks);
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                },
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                  ),
                );
              },
            );
          },
        );
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

/// 与 PageController 逐帧联动的学期进度线，手指移动多少，进度就移动多少。
class _WeekProgressIndicator extends StatelessWidget {
  final PageController controller;
  final int selectedWeek;
  final int totalWeeks;

  const _WeekProgressIndicator({
    required this.controller,
    required this.selectedWeek,
    required this.totalWeeks,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 3,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              var page = (selectedWeek - 1).toDouble();
              if (controller.hasClients &&
                  controller.position.hasContentDimensions) {
                page = controller.page ?? page;
              }
              final progress = totalWeeks <= 1
                  ? 1.0
                  : ((page + 1) / totalWeeks).clamp(0.0, 1.0).toDouble();
              return Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: theme.colorScheme.outlineVariant.withAlpha(105),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress,
                      child: ColoredBox(color: theme.colorScheme.primary),
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
}

class _WeekSelector extends StatelessWidget {
  final int selectedWeek;
  final int totalWeeks;
  final bool isCurrentWeek;
  final int currentWeek;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int>? onJumpToWeek;

  const _WeekSelector({
    required this.selectedWeek,
    required this.totalWeeks,
    required this.isCurrentWeek,
    required this.currentWeek,
    required this.onPrev,
    required this.onNext,
    this.onJumpToWeek,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left,
                size: 20, color: theme.colorScheme.primary),
            visualDensity: VisualDensity.compact,
            onPressed: selectedWeek > 1 ? onPrev : null,
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onJumpToWeek != null
                        ? () => _showWeekPicker(context)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 周次数字轻 crossfade，避免切周时瞬间跳变
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 150),
                            child: Text(
                              '第 $selectedWeek / $totalWeeks 周',
                              key: ValueKey('$selectedWeek-$totalWeeks'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration: onJumpToWeek != null
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                          ),
                          if (onJumpToWeek != null) ...[
                            const SizedBox(width: 2),
                            Icon(Icons.arrow_drop_down,
                                size: 16, color: theme.colorScheme.primary),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (isCurrentWeek) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary
                            .withAlpha((0.12 * 255).round()),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '本周',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!isCurrentWeek && onJumpToWeek != null)
            TextButton(
              onPressed: () => onJumpToWeek!(currentWeek),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('本周'),
            ),
          IconButton(
            icon: Icon(Icons.chevron_right,
                size: 20, color: theme.colorScheme.primary),
            visualDensity: VisualDensity.compact,
            onPressed: selectedWeek < totalWeeks ? onNext : null,
          ),
        ],
      ),
    );
  }

  void _showWeekPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('跳转到第几周',
                    style: Theme.of(context).textTheme.titleMedium),
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
                    final isSelected = week == selectedWeek;
                    return InkWell(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onJumpToWeek?.call(week);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).dividerColor,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$week',
                          style: TextStyle(
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface,
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
}

const _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

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
