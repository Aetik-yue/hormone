import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hormone/core/constants/app_constants.dart';
import 'package:hormone/data/providers/database_providers.dart';
import 'package:hormone/data/repositories/backup_repository.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';
import '../application/theme_mode_provider.dart';
import '../application/section_times_provider.dart';
import '../application/export_service.dart';

/// 项目 GitHub 仓库地址（支持我们）。
const String _githubUrl = 'https://github.com/Aetik-yue/hormone';

/// 设置页：主题切换、节次时间自定义、导入/导出、学期管理入口。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// 异步读取 App 版本号（如 "1.1.0 (13)"）。
  static final Future<String> _versionFuture = PackageInfo.fromPlatform().then(
    (p) => 'v${p.version} (${p.buildNumber})',
  );

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
          _AppearanceCard(
            mode: mode,
            onChanged: (next) =>
                ref.read(themeModeProvider.notifier).setThemeMode(next),
          ),

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
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('课程抓取使用说明'),
            subtitle: const Text('查看从登录教务系统到导入课程的完整步骤'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/import/guide'),
          ),
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
            subtitle: const Text('把全部学期和课程导出并分享保存'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _exportData(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('从备份恢复'),
            subtitle: const Text('用导出的 JSON 文件替换当前全部数据'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _restoreData(context, ref),
          ),
          const Divider(height: 1),

          // ── 关于 ──
          const _SectionHeader('关于'),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('GitHub 仓库'),
            subtitle: const Text('欢迎 Star 与反馈 Issue，支持项目持续开发'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openGithub(context),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: FutureBuilder<String>(
              future: _versionFuture,
              builder: (context, snap) => Text(snap.data ?? '…'),
            ),
          ),
        ],
      ),
    );
  }

  /// 打开 GitHub 仓库页面（外部浏览器）。
  Future<void> _openGithub(BuildContext context) async {
    final uri = Uri.parse(_githubUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开浏览器，请手动访问：$_githubUrl')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败：$e')),
        );
      }
    }
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
      await ref.read(exportServiceProvider).exportToJson();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  /// 选择备份文件 → 确认覆盖 → 全量恢复。
  Future<void> _restoreData(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      messenger.showSnackBar(const SnackBar(content: Text('无法读取所选文件')));
      return;
    }

    if (!context.mounted) return;
    // 解析校验：先确认这是合法备份，再询问是否覆盖（避免覆盖后才发现文件无效）。
    final String jsonText;
    final int previewSemesters;
    try {
      jsonText = String.fromCharCodes(bytes);
      final parsed = BackupFile.parse(jsonText);
      previewSemesters = parsed.semesters.length;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('备份文件无效：$e')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复备份？'),
        content: Text(
          '将用备份中的 $previewSemesters 个学期替换当前全部学期和课程，'
          '此操作不可撤销。确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      final result2 =
          await ref.read(backupRepositoryProvider).restore(jsonText);
      // 刷新依赖学期/课程数据的全部 Provider（桌面小组件由 _AppEffects
      // 监听这些 provider 集中触发刷新）。
      ref.invalidate(activeSemesterProvider);
      ref.invalidate(scheduleCoursesProvider);
      ref.invalidate(semestersProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              '已恢复 ${result2.semesterCount} 个学期、${result2.courseCount} 门课程'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('恢复失败：$e')));
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

/// 主题模式使用直接可见的分段按钮，避免把最常用的外观选项藏进下拉菜单。
class _AppearanceCard extends StatelessWidget {
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  const _AppearanceCard({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveBrightness = theme.brightness;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    effectiveBrightness == Brightness.dark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    size: 20,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('显示模式', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        mode == ThemeMode.system
                            ? '当前跟随系统使用${effectiveBrightness == Brightness.dark ? '深色' : '浅色'}模式'
                            : mode == ThemeMode.dark
                                ? '降低夜间使用时的屏幕眩光'
                                : '明亮清晰，适合日间查看课表',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined, size: 18),
                    label: Text('系统'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined, size: 18),
                    label: Text('浅色'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined, size: 18),
                    label: Text('深色'),
                  ),
                ],
                selected: {mode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => onChanged(selection.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 可选的课时时长（分钟）。
const _durationOptions = [30, 35, 40, 45, 50, 60, 90, 120];

/// 节次时间编辑器（Bottom Sheet）。
class _SectionTimeEditor extends ConsumerStatefulWidget {
  const _SectionTimeEditor();

  @override
  ConsumerState<_SectionTimeEditor> createState() => _SectionTimeEditorState();
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
                    onPressed: () => _showTemplatePicker(context, ref),
                    child: const Text('模板'),
                  ),
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
                  final sectionTime = times[section];
                  final startTime = sectionTime?.startTime ?? '';
                  final duration = sectionTime?.durationMinutes ??
                      AppConstants.defaultSectionDuration;
                  final endTime = sectionTime?.endTime ?? '';
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text('第 $section 节',
                              style: theme.textTheme.bodyMedium),
                        ),
                        InkWell(
                          onTap: () => _pickTime(context, section, startTime),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.dividerColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              startTime.isNotEmpty ? startTime : '未设置',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: _durationOptions.contains(duration)
                              ? duration
                              : null,
                          items: _durationOptions
                              .map((d) => DropdownMenuItem(
                                    value: d,
                                    child: Text('$d 分'),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              ref
                                  .read(sectionTimesProvider.notifier)
                                  .setSectionDuration(section, v);
                            }
                          },
                        ),
                        const Spacer(),
                        Text(
                          endTime.isNotEmpty ? '→ $endTime' : '',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                      ],
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
      ref.read(sectionTimesProvider.notifier).setSectionStart(section, timeStr);
    }
  }

  void _showTemplatePicker(BuildContext context, WidgetRef ref) {
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
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('选择节次模板',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const Divider(height: 1),
              ...sectionTimeTemplates.map((template) => ListTile(
                    title: Text(template.name),
                    subtitle: Text('${template.duration} 分钟/节'),
                    onTap: () {
                      ref
                          .read(sectionTimesProvider.notifier)
                          .applyTemplate(template);
                      Navigator.of(ctx).pop();
                    },
                  )),
            ],
          ),
        );
      },
    );
  }
}
