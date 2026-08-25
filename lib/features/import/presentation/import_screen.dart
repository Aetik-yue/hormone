import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hormone/features/import/application/import_provider.dart';
import 'package:hormone/features/import/domain/import_course.dart';
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
      onPressed:
          state.selectedCount > 0 ? () => notifier.confirmImport() : null,
      icon: const Icon(Icons.download_done),
      label: Text('导入 ${state.selectedCount} 门'),
    );
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

    // 已选课程中 pairwise 冲突检测，给出顶部提示。
    final conflicts = _conflictNames(state);

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
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '确认后，所选课程将替换当前学期的原有课表。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        if (conflicts.isNotEmpty) ImportConflictBanner(names: conflicts),
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

  /// 返回存在时间冲突的已选课程名称集合（用于高亮与提示）。
  Set<String> _conflictNames(ImportState state) {
    final selected = state.courses.where((c) => c.selected).toList();
    final names = <String>{};
    for (var i = 0; i < selected.length; i++) {
      for (var j = i + 1; j < selected.length; j++) {
        if (coursesConflict(selected[i], selected[j])) {
          names.add(selected[i].name);
          names.add(selected[j].name);
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
