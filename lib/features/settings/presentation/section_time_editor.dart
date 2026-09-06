import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hormone/core/constants/app_constants.dart';
import '../application/section_times_provider.dart';
import '../domain/section_time_shift.dart';

/// 可选的课时时长（分钟）。
const _durationOptions = [30, 35, 40, 45, 50, 60, 90, 120];

/// 节次时间编辑器（Bottom Sheet）。
class SectionTimeEditor extends ConsumerStatefulWidget {
  const SectionTimeEditor({super.key});

  @override
  ConsumerState<SectionTimeEditor> createState() => _SectionTimeEditorState();
}

class _SectionTimeEditorState extends ConsumerState<SectionTimeEditor> {
  bool _shiftFollowing = true;

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
                    onPressed:
                        () =>
                            ref
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
                itemCount: AppConstants.maxSections + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return SwitchListTile(
                      title: const Text('后续节次同步顺延'),
                      subtitle: const Text(
                        '修改第一节开始时间时，所有已设置节次一起前移或后移，保留课长、课间和午休间隔。',
                      ),
                      value: _shiftFollowing,
                      onChanged:
                          (value) => setState(() => _shiftFollowing = value),
                    );
                  }
                  final section = i;
                  final sectionTime = times[section];
                  final startTime = sectionTime?.startTime ?? '';
                  final duration =
                      sectionTime?.durationMinutes ??
                      AppConstants.defaultSectionDuration;
                  final endTime = sectionTime?.endTime ?? '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            '第 $section 节',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        InkWell(
                          key: ValueKey('section-start-$section'),
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
                          value:
                              _durationOptions.contains(duration)
                                  ? duration
                                  : null,
                          items:
                              _durationOptions
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d,
                                      child: Text('$d 分'),
                                    ),
                                  )
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
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
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
      },
    );
  }

  Future<void> _pickTime(
    BuildContext context,
    int section,
    String current,
  ) async {
    final parts = current.split(':');
    final initial =
        parts.length == 2
            ? TimeOfDay(
              hour: int.tryParse(parts[0]) ?? 8,
              minute: int.tryParse(parts[1]) ?? 0,
            )
            : const TimeOfDay(hour: 8, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText:
          section == 1 && _shiftFollowing ? '调整第一节并同步顺延' : '设置第 $section 节开始时间',
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      final timeStr =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      final notifier = ref.read(sectionTimesProvider.notifier);
      try {
        if (section == 1 && _shiftFollowing) {
          await notifier.shiftFromFirstStart(timeStr);
        } else {
          await notifier.setSectionStart(section, timeStr);
        }
      } on SectionTimeShiftException catch (error) {
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text('无法同步顺延'),
                content: Text(error.message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('知道了'),
                  ),
                ],
              ),
        );
      }
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
                child: Text(
                  '选择节次模板',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Divider(height: 1),
              ...sectionTimeTemplates.map(
                (template) => ListTile(
                  title: Text(template.name),
                  subtitle: Text('${template.duration} 分钟/节'),
                  onTap: () {
                    ref
                        .read(sectionTimesProvider.notifier)
                        .applyTemplate(template);
                    Navigator.of(ctx).pop();
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
