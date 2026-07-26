import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/features/course/application/course_form_provider.dart';
import 'package:hormone/data/providers/database_providers.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';
import 'package:hormone/features/widget/application/widget_service.dart';

/// 卡片可选配色（柔和且彼此区分）。
const List<int> _palette = [
  0xFF5B8DEF,
  0xFF27AE60,
  0xFFF2994A,
  0xFF9B51E0,
  0xFFEB5757,
  0xFF2D9CDB,
  0xFFF2C94C,
  0xFF56CCF2,
  0xFFBB6BD9,
  0xFF6FCF97,
];

const List<String> _weekdayLabels = [
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日'
];

class CourseEditScreen extends ConsumerStatefulWidget {
  final String? courseId;
  const CourseEditScreen({super.key, this.courseId});

  @override
  ConsumerState<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends ConsumerState<CourseEditScreen> {
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final initAsync = ref.watch(courseInitialProvider(widget.courseId));
    final isEdit = widget.courseId != null && widget.courseId!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: Text(isEdit ? '编辑课程' : '添加课程'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '保存',
            onPressed: () => _save(context),
          ),
        ],
      ),
      body: initAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (initial) {
          if (!_initialized) {
            _initialized = true;
            Future.microtask(
              () => ref.read(courseFormProvider.notifier).init(initial),
            );
          }
          return CourseFormBody(initial: initial, isEdit: isEdit);
        },
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final course = ref.read(courseFormProvider);
    if (course.name.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写课程名称')),
      );
      return;
    }
    bool ok;
    try {
      ok = await ref.read(courseFormProvider.notifier).save();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在「学期管理」中创建学期')),
      );
      return;
    }
    ref.read(widgetServiceProvider).updateTodayWidget();
    if (context.mounted) context.pop();
  }
}

class CourseFormBody extends ConsumerStatefulWidget {
  final Course initial;
  final bool isEdit;
  const CourseFormBody({
    super.key,
    required this.initial,
    required this.isEdit,
  });

  @override
  ConsumerState<CourseFormBody> createState() => _CourseFormBodyState();
}

class _CourseFormBodyState extends ConsumerState<CourseFormBody> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _teacherCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial.name);
    _teacherCtrl = TextEditingController(text: widget.initial.teacher ?? '');
    _locationCtrl = TextEditingController(text: widget.initial.location ?? '');
    _notesCtrl = TextEditingController(text: widget.initial.notes ?? '');

    _nameCtrl.addListener(
      () => ref.read(courseFormProvider.notifier).setName(_nameCtrl.text),
    );
    _teacherCtrl.addListener(
      () => ref.read(courseFormProvider.notifier).setTeacher(_teacherCtrl.text),
    );
    _locationCtrl.addListener(
      () =>
          ref.read(courseFormProvider.notifier).setLocation(_locationCtrl.text),
    );
    _notesCtrl.addListener(
      () => ref.read(courseFormProvider.notifier).setNotes(_notesCtrl.text),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _teacherCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseFormProvider);
    final semester = ref.watch(activeSemesterProvider);
    final totalWeeks = semester.whenOrNull(data: (s) => s?.totalWeeks) ?? 18;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _FieldLabel('课程名称'),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            hintText: '如：高等数学',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        const _FieldLabel('教师'),
        TextField(
          controller: _teacherCtrl,
          decoration: const InputDecoration(
            hintText: '选填',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        const _FieldLabel('教室'),
        TextField(
          controller: _locationCtrl,
          decoration: const InputDecoration(
            hintText: '选填，如：教三-201',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        const _FieldLabel('星期'),
        Wrap(
          spacing: 8,
          children: List.generate(7, (i) {
            final day = i + 1;
            final selected = course.dayOfWeek == day;
            return ChoiceChip(
              label: Text(_weekdayLabels[i]),
              selected: selected,
              onSelected: (_) =>
                  ref.read(courseFormProvider.notifier).setDayOfWeek(day),
            );
          }),
        ),
        const SizedBox(height: 20),
        const _FieldLabel('节次'),
        Row(
          children: [
            Expanded(
              child: _SectionDropdown(
                label: '起始',
                value: course.startSection,
                sectionTimes: ref.watch(sectionTimesProvider),
                onChanged: (v) =>
                    ref.read(courseFormProvider.notifier).setStartSection(v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SectionDropdown(
                label: '结束',
                value: course.endSection,
                sectionTimes: ref.watch(sectionTimesProvider),
                onChanged: (v) =>
                    ref.read(courseFormProvider.notifier).setEndSection(v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _FieldLabel('上课周次'),
        Row(
          children: [
            TextButton(
              onPressed: () => ref
                  .read(courseFormProvider.notifier)
                  .setAllWeeks(List.generate(totalWeeks, (i) => i + 1)),
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(courseFormProvider.notifier).clearWeeks(),
              child: const Text('清空'),
            ),
            const Spacer(),
            Text('已选 ${course.weeks.length} 周',
                style: theme.textTheme.labelSmall),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(totalWeeks, (i) {
            final w = i + 1;
            final selected = course.weeks.contains(w);
            return FilterChip(
              label: Text('$w'),
              selected: selected,
              onSelected: (_) =>
                  ref.read(courseFormProvider.notifier).toggleWeek(w),
            );
          }),
        ),
        const SizedBox(height: 20),
        const _FieldLabel('卡片颜色'),
        Wrap(
          spacing: 10,
          children: _palette.map((c) {
            final selected = course.colorValue == c;
            return InkWell(
              onTap: () =>
                  ref.read(courseFormProvider.notifier).setColor(c),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(
                          color: theme.colorScheme.onSurface,
                          width: 2,
                        )
                      : null,
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const _FieldLabel('备注'),
        TextField(
          controller: _notesCtrl,
          decoration: const InputDecoration(
            hintText: '选填',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        if (widget.isEdit) ...[
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('删除课程',
                style: TextStyle(color: Colors.red)),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _delete(BuildContext context) async {
    final id = widget.initial.id;
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除课程'),
        content: const Text('确定要删除这门课程吗？此操作不可撤销。'),
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
        await ref.read(courseRepositoryProvider).delete(id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：$e')),
          );
        }
        return;
      }
      ref.read(widgetServiceProvider).updateTodayWidget();
      if (context.mounted) context.pop();
    }
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}

class _SectionDropdown extends StatelessWidget {
  final String label;
  final int value;
  final Map<int, SectionTime> sectionTimes;
  final void Function(int?) onChanged;

  const _SectionDropdown({
    required this.label,
    required this.value,
    required this.sectionTimes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final maxSections = sectionTimes.length;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value > 0 && value <= maxSections ? value : null,
          isExpanded: true,
          items: List.generate(maxSections, (i) {
            final s = i + 1;
            final sectionTime = sectionTimes[s];
            final display = sectionTime != null &&
                    sectionTime.timeRange.isNotEmpty
                ? '第$s节 · ${sectionTime.timeRange}'
                : '第$s节';
            return DropdownMenuItem(
              value: s,
              child: Text(display),
            );
          }),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
