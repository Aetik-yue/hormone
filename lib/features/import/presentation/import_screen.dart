import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hormone/core/models/course.dart';
import 'package:hormone/data/providers/database_providers.dart';
import 'package:hormone/features/import/application/import_provider.dart';
import 'package:hormone/features/import/domain/import_course.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';
import 'import_confirm_dialog.dart';
import 'import_preview_list.dart';

/// 课程导入页（Phase 5）。
/// 流程：选择文件 → 解析 → 预览勾选 → 确认导入。
class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('导入课程'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(context, ref, state, theme),
      floatingActionButton: _buildFab(context, ref, state),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ImportState state,
    ThemeData theme,
  ) {
    switch (state.status) {
      case ImportStatus.idle:
      case ImportStatus.picking:
        return _IdleView(
          busy: state.status == ImportStatus.picking,
          onPick: () => ref.read(importProvider.notifier).pickAndParse(),
        );
      case ImportStatus.parsing:
      case ImportStatus.importing:
        return const Center(child: CircularProgressIndicator());
      case ImportStatus.preview:
        return _PreviewList(state: state);
      case ImportStatus.done:
        return _DoneView(
          count: state.importedCount,
          onDone: () => Navigator.of(context).pop(),
        );
      case ImportStatus.error:
        return _ErrorView(
          message: state.errorMessage ?? '未知错误',
          onRetry: () => ref.read(importProvider.notifier).reset(),
        );
    }
  }

  Widget? _buildFab(
    BuildContext context,
    WidgetRef ref,
    ImportState state,
  ) {
    if (state.status != ImportStatus.preview) return null;
    final notifier = ref.read(importProvider.notifier);
    return FloatingActionButton.extended(
      onPressed: state.selectedCount > 0
          ? () => _confirmAndImport(context, ref, state, notifier)
          : null,
      icon: const Icon(Icons.download_done),
      label: Text('导入 ${state.selectedCount} 门'),
    );
  }

  /// 二次确认后再执行导入（替换/合并均需确认）。
  Future<void> _confirmAndImport(
    BuildContext context,
    WidgetRef ref,
    ImportState state,
    ImportNotifier notifier,
  ) async {
    final existing = await _existingCourseCount(ref);
    if (!context.mounted) return;
    final ok = await showImportConfirmDialog(
      context,
      mode: state.mode,
      importCount: state.selectedCount,
      existingCount: existing,
    );
    if (ok) await notifier.confirmImport();
  }
}

/// 当前激活学期已有的课程数（用于确认弹窗展示）。
Future<int> _existingCourseCount(WidgetRef ref) async {
  final repo = ref.read(courseRepositoryProvider);
  final semester = await ref.read(semesterRepositoryProvider).getActiveSemester();
  if (semester == null) return 0;
  return (await repo.getCourses(semester.id)).length;
}

/// 空闲/选择文件视图。
class _IdleView extends StatelessWidget {
  final bool busy;
  final VoidCallback onPick;

  const _IdleView({required this.busy, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.file_upload_outlined,
                size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text('从文件导入课程', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '支持 .ics（日历导出）与 .json（课程模板）。',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: busy ? null : onPick,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open),
              label: Text(busy ? '请选择文件…' : '选择文件'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 解析后的预览列表，可逐条勾选。
class _PreviewList extends ConsumerWidget {
  final ImportState state;

  const _PreviewList({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(importProvider.notifier);
    // 合并模式需要与现有课表比对冲突；替换模式会清空现有课表，无意义。
    final existingCourses =
        state.mode == ImportMode.merge
            ? ref.watch(scheduleCoursesProvider).valueOrNull ?? const <Course>[]
            : const <Course>[];

    // 内部 pairwise 冲突 +（合并模式下）与现有课表的冲突。
    final conflicts = _conflictNames(state, existingCourses);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text('共解析 ${state.courses.length} 门',
                  style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: () => notifier.setAllSelected(true),
                child: const Text('全选'),
              ),
              TextButton(
                onPressed: () => notifier.setAllSelected(false),
                child: const Text('全不选'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ImportMode>(
            segments: const [
              ButtonSegment(
                value: ImportMode.replace,
                icon: Icon(Icons.restart_alt, size: 18),
                label: Text('替换'),
              ),
              ButtonSegment(
                value: ImportMode.merge,
                icon: Icon(Icons.library_add_outlined, size: 18),
                label: Text('合并'),
              ),
            ],
            selected: {state.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => notifier.setMode(s.first),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            state.mode == ImportMode.merge
                ? '合并模式：保留现有课表，追加所选课程。'
                : '替换模式：所选课程将替换当前学期的原有课表。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        if (conflicts.isNotEmpty)
          ImportConflictBanner(
            names: conflicts,
            reason: state.mode == ImportMode.merge
                ? '与现有课程或彼此同时段重叠'
                : '所选课程彼此同时段重叠',
          ),
        const Divider(height: 1),
        Expanded(
          child: ImportPreviewList(
            courses: state.courses,
            conflictedNames: conflicts,
            onToggle: (i) => notifier.toggleSelected(i),
          ),
        ),
      ],
    );
  }

  /// 返回存在时间冲突的已选课程名称集合（内部冲突 + 与现有课表冲突）。
  Set<String> _conflictNames(
    ImportState state,
    List<Course> existingCourses,
  ) {
    final selected = state.courses.where((c) => c.selected).toList();
    final names = <String>{};
    for (var i = 0; i < selected.length; i++) {
      for (var j = i + 1; j < selected.length; j++) {
        if (coursesConflict(selected[i], selected[j])) {
          names
            ..add(selected[i].name)
            ..add(selected[j].name);
        }
      }
      for (final e in existingCourses) {
        if (conflictsWithCourse(selected[i], e)) {
          names.add(selected[i].name);
        }
      }
    }
    return names;
  }
}

class _DoneView extends StatelessWidget {
  final int count;
  final VoidCallback onDone;

  const _DoneView({required this.count, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 72, color: Color(0xFF34B37E)),
            const SizedBox(height: 24),
            Text('已用 $count 门课程替换当前课表', style: theme.textTheme.titleLarge),
            const SizedBox(height: 24),
            FilledButton(onPressed: onDone, child: const Text('完成')),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 72, color: theme.colorScheme.error),
            const SizedBox(height: 24),
            Text('导入失败', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('返回')),
          ],
        ),
      ),
    );
  }
}
