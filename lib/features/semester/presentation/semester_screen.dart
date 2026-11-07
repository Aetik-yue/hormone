import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:recess/core/models/semester.dart';
import 'package:recess/core/utils/week_calculator.dart';
import 'package:recess/core/widgets/load_failed_view.dart';
import 'package:recess/features/semester/application/semester_form_provider.dart';
import 'package:recess/features/semester/application/semester_mutations.dart';
import 'package:recess/features/semester/application/semester_providers.dart';

class SemesterScreen extends ConsumerWidget {
  final DateTime Function()? now;
  const SemesterScreen({super.key, this.now});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semestersAsync = ref.watch(semestersProvider);
    final activeAsync = ref.watch(activeSemesterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('学期管理'),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: semestersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // 学期列表与当前学期任一失败都进入重试态；重试同时覆盖两个数据源。
        error: (e, _) => LoadFailedView(
          title: '学期加载失败',
          message: '学期数据没有读取出来，点击重试重新加载',
          onRetry: () {
            ref.invalidate(activeSemesterProvider);
            ref.invalidate(semestersProvider);
          },
        ),
        data: (semesters) {
          final activeId = activeAsync.whenOrNull(data: (s) => s?.id);
          if (semesters.isEmpty) {
            return Center(
              child: Text('还没有学期，点击右下角添加',
                  style: TextStyle(color: Theme.of(context).hintColor)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: semesters.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final s = semesters[i];
              final isActive = s.id == activeId;
              return _SemesterCard(
                semester: s,
                isActive: isActive,
                onTap: () => _openEdit(context, ref, s),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEdit(context, ref, null),
        tooltip: '添加学期',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openEdit(BuildContext context, WidgetRef ref, Semester? initial) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SemesterEditSheet(initial: initial, now: now),
    ).then((changed) {
      if (changed == true) {
        ref.invalidate(semesterFormProvider);
      }
    });
  }
}

class _SemesterCard extends StatelessWidget {
  final Semester semester;
  final bool isActive;
  final VoidCallback onTap;

  const _SemesterCard({
    required this.semester,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final week = teachingWeekOf(semester, now);
    final weekLabel = week != null
        ? '第 $week 周'
        : (currentWeekOf(semester, now) < 1 ? '未开学' : '已结束');
    final end = lastSemesterDay(semester);
    final range =
        '${DateFormat('yyyy-MM-dd').format(semester.startDate)} ~ ${DateFormat('yyyy-MM-dd').format(end)}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: isActive
              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(semester.name.isEmpty ? '未命名学期' : semester.name,
                          style: theme.textTheme.titleMedium),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withAlpha((0.12 * 255).round()),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('当前',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              )),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(range, style: theme.textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Text('共 ${semester.totalWeeks} 周 · $weekLabel',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.hintColor)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.hintColor),
          ],
        ),
      ),
    );
  }
}

/// 学期新增/编辑底部弹层。
class SemesterEditSheet extends ConsumerStatefulWidget {
  final Semester? initial;
  final DateTime Function()? now;
  final bool fromImport;
  const SemesterEditSheet({
    super.key,
    this.initial,
    this.now,
    this.fromImport = false,
  });

  @override
  ConsumerState<SemesterEditSheet> createState() => _SemesterEditSheetState();
}

class _SemesterEditSheetState extends ConsumerState<SemesterEditSheet> {
  late final TextEditingController _nameCtrl;
  late bool _activate;
  bool _overrideOn = false;

  @override
  void initState() {
    super.initState();
    _activate = widget.initial == null;
    final today = (widget.now ?? DateTime.now)();
    final nextMonday = DateTime(
      today.year,
      today.month,
      today.day + (DateTime.monday - today.weekday + 7) % 7,
    );
    final s = widget.initial ??
        Semester(id: '', name: '', startDate: nextMonday, totalWeeks: 18);
    _nameCtrl = TextEditingController(text: s.name);
    _overrideOn = s.currentWeekOverride != null;
    // initState 中不可修改 Provider 状态（riverpod 禁止在 Widget 生命周期内修改），
    // 延迟到微任务执行，待当前 build 完成后再初始化表单。
    Future.microtask(() {
      if (mounted) ref.read(semesterFormProvider.notifier).init(s);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semester = ref.watch(semesterFormProvider);
    final isEdit = widget.initial != null;
    final activeId = ref.watch(activeSemesterProvider).valueOrNull?.id;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '学期名称',
                hintText: '如：2026春学期',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) =>
                  ref.read(semesterFormProvider.notifier).setName(v),
            ),
            const SizedBox(height: 16),
            _Row(
              label: '开学日期',
              child: TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: semester.startDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    ref
                        .read(semesterFormProvider.notifier)
                        .setStartDate(picked);
                  }
                },
                child: Text(
                  DateFormat('yyyy-MM-dd').format(semester.startDate),
                ),
              ),
            ),
            _Row(
              label: '总周数',
              child: _Stepper(
                value: semester.totalWeeks,
                min: 1,
                max: 30,
                onChanged: (v) => ref
                    .read(semesterFormProvider.notifier)
                    .setTotalWeeks(v),
              ),
            ),
            _Row(
              label: '当前周',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: _overrideOn,
                    onChanged: (v) => setState(() {
                      _overrideOn = v;
                      if (!v) {
                        ref
                            .read(semesterFormProvider.notifier)
                            .setCurrentWeekOverride(null);
                      } else {
                        // 默认使用计算出的当前周，而非最后一周
                        final computedWeek = computeCurrentWeek(
                            semester.startDate, DateTime.now());
                        final defaultWeek =
                            clampWeek(computedWeek, semester.totalWeeks);
                        ref
                            .read(semesterFormProvider.notifier)
                            .setCurrentWeekOverride(
                                semester.currentWeekOverride ?? defaultWeek);
                      }
                    }),
                  ),
                  if (_overrideOn)
                    _Stepper(
                      value: semester.currentWeekOverride ??
                          clampWeek(
                              computeCurrentWeek(
                                  semester.startDate, DateTime.now()),
                              semester.totalWeeks),
                      min: 1,
                      max: semester.totalWeeks,
                      onChanged: (v) => ref
                          .read(semesterFormProvider.notifier)
                          .setCurrentWeekOverride(v),
                    ),
                ],
              ),
            ),
            // 学期管理页新建时可选择是否设为当前学期。
            if (!isEdit && !widget.fromImport)
              SwitchListTile(
                title: const Text('保存后设为当前学期'),
                value: _activate,
                onChanged: (v) => setState(() => _activate = v),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: semester.name.trim().isEmpty ? null : () async {
                  try {
                    await ref.read(semesterFormProvider.notifier).save(
                          activate: widget.fromImport || _activate,
                        );
                    if (context.mounted) Navigator.of(context).pop(true);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('保存失败：$e')),
                      );
                    }
                  }
                },
                child: Text(isEdit ? '保存' : '创建'),
              ),
            ),
            if (isEdit && activeId != null && widget.initial!.id != activeId)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    try {
                      await ref.read(semesterMutationsProvider).save(
                            widget.initial!,
                            activate: true,
                          );
                      if (context.mounted) Navigator.of(context).pop(true);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('保存失败：$e')),
                        );
                      }
                    }
                  },
                  child: const Text('设为当前学期'),
                ),
              ),
            if (isEdit)
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => _delete(context, ref),
                  child: Text('删除学期',
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除学期'),
        content: const Text('该学期下的课程也会一并删除，且不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(semesterFormProvider.notifier).delete();
        if (context.mounted) Navigator.of(context).pop(true);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：$e')),
          );
        }
      }
    }
  }
}

class _Row extends StatelessWidget {
  final String label;
  final Widget child;
  const _Row({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(label,
                  style: Theme.of(context).textTheme.labelMedium),
            ),
            Expanded(child: Align(alignment: Alignment.centerRight, child: child)),
          ],
        ),
      );
}

class _Stepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final void Function(int) onChanged;
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          Text('$value', style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      );
}
