import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hormone/core/constants/app_constants.dart';
import '../application/theme_mode_provider.dart';
import '../application/section_times_provider.dart';
import '../application/export_service.dart';

/// 设置页：主题切换、节次时间自定义、导入/导出、学期管理入口。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          // ── 外观 ──
          const _SectionHeader('外观'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题'),
            subtitle: const Text('浅色 / 深色 / 跟随系统'),
            trailing: DropdownButton<ThemeMode>(
              value: mode,
              onChanged: (m) =>
                  ref.read(themeModeProvider.notifier).setThemeMode(m!),
              items: const [
                DropdownMenuItem(
                    value: ThemeMode.system, child: Text('跟随系统')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── 学期 ──
          const _SectionHeader('学期'),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('学期管理'),
            subtitle: const Text('创建、切换、编辑学期'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/semester'),
          ),
          const Divider(height: 1),

          // ── 节次时间 ──
          const _SectionHeader('节次时间'),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('自定义节次时间'),
            subtitle: const Text('设置每节课的开始时间'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showSectionTimeEditor(context, ref),
          ),
          const Divider(height: 1),

          // ── 数据 ──
          const _SectionHeader('数据'),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('从教务系统导入'),
            subtitle: const Text('登录学校教务系统，一键抓取课表'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/import/webview'),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('导入课程'),
            subtitle: const Text('从 .ics / .json 文件批量导入'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/import'),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('导出备份'),
            subtitle: const Text('导出全部学期和课程为 JSON 文件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _exportData(context, ref),
          ),
        ],
      ),
    );
  }

  void _showSectionTimeEditor(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _SectionTimeEditor(),
    );
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await ref.read(exportServiceProvider).exportToJson();
      messenger.showSnackBar(
        SnackBar(content: Text('已导出到：$path')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 节次时间编辑器（Bottom Sheet）。
class _SectionTimeEditor extends ConsumerStatefulWidget {
  const _SectionTimeEditor();

  @override
  ConsumerState<_SectionTimeEditor> createState() =>
      _SectionTimeEditorState();
}

class _SectionTimeEditorState extends ConsumerState<_SectionTimeEditor> {
  @override
  Widget build(BuildContext context) {
    final times = ref.watch(sectionTimesProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('节次时间设置', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () => ref
                        .read(sectionTimesProvider.notifier)
                        .resetToDefault(),
                    child: const Text('恢复默认'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: AppConstants.maxSections,
                itemBuilder: (context, i) {
                  final section = i + 1;
                  final time = times[section] ?? '';
                  return ListTile(
                    title: Text('第 $section 节'),
                    trailing: InkWell(
                      onTap: () => _pickTime(context, section, time),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          time.isNotEmpty ? time : '未设置',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickTime(
      BuildContext context, int section, String current) async {
    final parts = current.split(':');
    final initial = parts.length == 2
        ? TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 8,
            minute: int.tryParse(parts[1]) ?? 0,
          )
        : const TimeOfDay(hour: 8, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final timeStr =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      ref.read(sectionTimesProvider.notifier).setSectionTime(section, timeStr);
    }
  }
}
