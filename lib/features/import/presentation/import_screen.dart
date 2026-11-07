import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recess/core/models/course.dart';
import 'package:recess/core/models/import_diagnostic.dart';
import 'package:recess/data/providers/database_providers.dart';
import 'package:recess/features/import/application/import_provider.dart';
import 'package:recess/features/import/domain/import_course.dart';
import 'package:recess/features/semester/application/semester_providers.dart';
import 'import_confirm_dialog.dart';
import 'import_preview_list.dart';
import 'import_target_semester.dart';

/// 课程导入页（Phase 5）。
/// 流程：选择文件 → 解析 → 预览勾选 → 确认导入。
class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(importProvider, (previous, next) {
      if (next.status == ImportStatus.preview &&
          next.errorMessage != null &&
          previous?.status == ImportStatus.importing) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
      }
    });
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
        return Column(
          children: [
            if (state.status == ImportStatus.idle)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ImportTargetSemester(),
              ),
            Expanded(
              child: _IdleView(
                busy: state.status == ImportStatus.picking,
                onPick: () => ref.read(importProvider.notifier).pickAndParse(),
              ),
            ),
          ],
        );
      case ImportStatus.parsing:
      case ImportStatus.importing:
        return const Center(child: CircularProgressIndicator());
      case ImportStatus.preview:
        return _PreviewList(state: state);
      case ImportStatus.done:
        return _DoneView(
          mode: state.mode,
          count: state.importedCount,
          diagnostics: state.diagnostics,
          onDone: () => Navigator.of(context).pop(),
        );
      case ImportStatus.error:
        return _ErrorView(
          message: state.errorMessage ?? '未知错误',
          diagnostics: state.diagnostics,
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
          ? () => _confirmAndImport(context, ref, notifier)
          : null,
      icon: const Icon(Icons.download_done),
      label: Text('导入 ${state.selectedCount} 门'),
    );
  }

  /// 二次确认后再执行导入（替换/合并均需确认）。
  Future<void> _confirmAndImport(
    BuildContext context,
    WidgetRef ref,
    ImportNotifier notifier,
  ) async {
    final submission = await notifier.prepareImport();
    if (submission == null || submission.courses.isEmpty) return;
    final existing = (await ref.read(courseRepositoryProvider)
        .getCourses(submission.semesterId)).length;
    if (!context.mounted) return;
    final ok = await showImportConfirmDialog(
      context,
      mode: submission.mode,
      importCount: submission.courses.length,
      existingCount: existing,
    );
    if (ok) await notifier.confirmImport(submission);
  }
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
    final conflicts = conflictNames(state.courses, existingCourses);

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
        ImportModeSelector(
          mode: state.mode,
          onChanged: notifier.setMode,
        ),
        if (state.diagnostics.isNotEmpty)
          ImportDiagnosticsCard(diagnostics: state.diagnostics),
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
}

class _DoneView extends StatelessWidget {
  final ImportMode mode;
  final int count;
  final List<ImportDiagnostic> diagnostics;
  final VoidCallback onDone;

  const _DoneView({
    required this.mode,
    required this.count,
    required this.diagnostics,
    required this.onDone,
  });

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
            Text(
              mode == ImportMode.merge
                  ? '已在现有课表中追加 $count 门课程'
                  : '已用 $count 门课程替换当前课表',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (diagnostics.isNotEmpty) ...[
              const SizedBox(height: 16),
              ImportDiagnosticsCard(diagnostics: diagnostics),
            ],
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
  final List<ImportDiagnostic> diagnostics;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.diagnostics,
    required this.onRetry,
  });

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
            if (diagnostics.isNotEmpty) ...[
              const SizedBox(height: 16),
              // 零有效课程：直接展开具体原因，便于判断改文件还是换文件。
              ImportDiagnosticsCard(
                diagnostics: diagnostics,
                initiallyExpanded: true,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('返回')),
          ],
        ),
      ),
    );
  }
}

/// 导入诊断摘要卡片：「N 条记录未完整导入」+ 可展开的逐条原因。
///
/// 预览、错误、完成页共用；只呈现信息，不阻断有效课程的导入。
class ImportDiagnosticsCard extends StatefulWidget {
  final List<ImportDiagnostic> diagnostics;

  /// 错误页（零有效课程）直接展开具体原因。
  final bool initiallyExpanded;

  const ImportDiagnosticsCard({
    super.key,
    required this.diagnostics,
    this.initiallyExpanded = false,
  });

  @override
  State<ImportDiagnosticsCard> createState() => _ImportDiagnosticsCardState();
}

class _ImportDiagnosticsCardState extends State<ImportDiagnosticsCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skipped = widget.diagnostics
        .where((d) => d.kind == ImportDiagnosticKind.skipped)
        .length;
    final partial = widget.diagnostics.length - skipped;
    final parts = [
      if (skipped > 0) '跳过 $skipped 条',
      if (partial > 0) '部分忽略 $partial 条',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 18, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '未完整导入：${parts.join('，')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起' : '查看原因'),
              ),
            ],
          ),
          if (_expanded)
            ...widget.diagnostics.map(
              (d) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  d.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
