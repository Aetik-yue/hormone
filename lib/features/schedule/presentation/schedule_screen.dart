import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/schedule_providers.dart';
import '../../semester/application/semester_providers.dart';
import '../../../core/utils/week_calculator.dart';
import '../../../data/providers/database_providers.dart';
import '../../widget/application/widget_service.dart';
import 'week_view.dart';

/// 仅同步一次：进入课程表主页即刷新桌面小组件（今日课程）。
bool _widgetSynced = false;

/// 课程表主页：学期选择 + 周选择器 + 周视图时间轴。
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final isCurrentWeek =
        computedWeek != null && computedWeek == selectedWeek;

    if (!_widgetSynced) {
      _widgetSynced = true;
      Future.microtask(
        () => ref.read(widgetServiceProvider).updateTodayWidget(),
      );
    }

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
                  color: Theme.of(context).hintColor,
                ),
              ],
            ),
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          // 左滑 → 下一周，右滑 → 上一周
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -300) {
            ref.read(selectedWeekProvider.notifier).nextWeek(totalWeeks);
          } else if (details.primaryVelocity! > 300) {
            ref.read(selectedWeekProvider.notifier).prevWeek();
          }
        },
        child: Column(
          children: [
            _WeekSelector(
              selectedWeek: selectedWeek,
              totalWeeks: totalWeeks,
              isCurrentWeek: isCurrentWeek,
              currentWeek: computedWeek ?? 1,
              onPrev: () =>
                  ref.read(selectedWeekProvider.notifier).prevWeek(),
              onNext: () =>
                  ref.read(selectedWeekProvider.notifier).nextWeek(totalWeeks),
              onJumpToWeek: (week) =>
                  ref.read(selectedWeekProvider.notifier).goTo(week),
            ),
            const Expanded(child: WeekView()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/course/edit'),
        tooltip: '添加课程',
        child: const Icon(Icons.add),
      ),
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
                            Text('切换学期',
                                style: theme.textTheme.titleMedium),
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
                                  final repo = ref
                                      .read(semesterRepositoryProvider);
                                  await repo.setActive(s.id);
                                  ref.invalidate(activeSemesterProvider);
                                  ref.invalidate(scheduleCoursesProvider);
                                  // 切换学期后重置到当前周
                                  ref
                                      .read(selectedWeekProvider.notifier)
                                      .goTo(computeCurrentWeek(
                                          s.startDate, DateTime.now()));
                                  ref
                                      .read(widgetServiceProvider)
                                      .updateTodayWidget();
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
            icon: const Icon(Icons.chevron_left, size: 20),
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
                          Text(
                            '第 $selectedWeek / $totalWeeks 周',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: onJumpToWeek != null
                                  ? TextDecoration.underline
                                  : null,
                            ),
                          ),
                          if (onJumpToWeek != null) ...[
                            const SizedBox(width: 2),
                            Icon(Icons.arrow_drop_down,
                                size: 16, color: theme.hintColor),
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
            icon: const Icon(Icons.chevron_right, size: 20),
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
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
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
