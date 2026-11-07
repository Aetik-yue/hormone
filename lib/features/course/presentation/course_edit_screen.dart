import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:recess/core/constants/app_constants.dart';
import 'package:recess/core/models/course.dart';
import 'package:recess/core/models/course_platform.dart';
import 'package:recess/core/widgets/load_failed_view.dart';
import 'package:recess/features/course/application/course_form_provider.dart';
import 'package:recess/features/course/application/course_platforms_provider.dart';
import 'package:recess/features/course/domain/unsaved_course_changes.dart';
import 'package:recess/features/course/presentation/course_platform_display.dart';
import 'package:recess/data/providers/database_providers.dart';
import 'package:recess/features/semester/application/semester_providers.dart';
import 'package:recess/features/settings/application/section_times_provider.dart';

class CourseEditScreen extends ConsumerStatefulWidget {
  final String? courseId;
  const CourseEditScreen({super.key, this.courseId});

  @override
  ConsumerState<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends ConsumerState<CourseEditScreen> {
  bool _initialized = false;
  Course? _initialCourse;
  List<CoursePlatform>? _initialPlatforms;

  @override
  Widget build(BuildContext context) {
    final initAsync = ref.watch(courseInitialProvider(widget.courseId));
    final isCopy = widget.courseId?.startsWith('copy:') ?? false;
    final isEdit = widget.courseId != null && widget.courseId!.isNotEmpty && !isCopy;
    final hasChanges = _hasUnsavedChanges();
    // 平台区块在列表底部，首帧可能不在屏内而未构建；由页面持有平台表单，
    // 避免 autoDispose 在 init 解析期间回收它，滚到区块时拿到空白的新实例。
    ref.watch(coursePlatformsFormProvider.notifier);

    return PopScope<Object?>(
      // 路由级退出保护：关闭按钮、系统返回键与返回手势都经过这里。
      canPop: !hasChanges,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.maybePop(context),
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
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: initAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            // 初始化失败：易懂说明 + 重试；重试按当前路由参数重新执行初始化，
            // 成功后仍走原有「仅初始化一次」的表单与课程平台流程。
            error: (e, _) => LoadFailedView(
              title: '课程加载失败',
              message: '课程数据没有读取出来，点击重试重新加载',
              onRetry: () =>
                  ref.invalidate(courseInitialProvider(widget.courseId)),
            ),
            data: (initial) {
              if (!_initialized) {
                _initialized = true;
                _initialCourse = initial;
                Future.microtask(() async {
                  ref.read(courseFormProvider.notifier).init(initial);
                  await ref.read(coursePlatformsFormProvider.notifier).init(
                        semesterId: initial.semesterId,
                        courseName: initial.name,
                        originalName: initial.id.isEmpty ? null : initial.name,
                      );
                  if (!mounted) return;
                  setState(() {
                    _initialPlatforms = List.unmodifiable(
                      ref.read(coursePlatformsFormProvider),
                    );
                  });
                });
              }
              return CourseFormBody(initial: initial, isEdit: isEdit);
            },
          ),
        ),
      ),
    );
  }

  /// 草稿与初始快照是否存在实际差异（平台基线在解析完成后才有）。
  bool _hasUnsavedChanges() {
    final initial = _initialCourse;
    final initialPlatforms = _initialPlatforms;
    if (initial == null || initialPlatforms == null) return false;
    return hasUnsavedCourseChanges(
      draft: ref.watch(courseFormProvider),
      initial: initial,
      platforms: ref.watch(coursePlatformsFormProvider),
      initialPlatforms: initialPlatforms,
    );
  }

  Future<void> _handlePopInvoked(bool didPop, Object? result) async {
    if (didPop) return;
    if (context.mounted && await _confirmDiscard() && context.mounted) {
      context.pop();
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('你有未保存的修改，确定要放弃吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _save(BuildContext context) async {
    final course = ref.read(courseFormProvider);
    if (course.name.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写课程名称')),
      );
      return;
    }
    bool? ok;
    try {
      ok = await ref.read(courseFormProvider.notifier).save(
            platforms: ref
                .read(coursePlatformsFormProvider.notifier)
                .pendingForCurrentName,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
      return;
    }
    if (ok == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一周，否则课程不会显示')),
      );
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在「学期管理」中创建学期')),
      );
      return;
    }
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

    _nameCtrl.addListener(() {
      ref.read(courseFormProvider.notifier).setName(_nameCtrl.text);
      // 平台按课程名归属：名字一变，列表跟着换成新名字下的平台。
      ref
          .read(coursePlatformsFormProvider.notifier)
          .setCourseName(_nameCtrl.text);
    });
    _teacherCtrl.addListener(() {
      ref.read(courseFormProvider.notifier).setTeacher(_teacherCtrl.text);
    });
    _locationCtrl.addListener(() {
      ref.read(courseFormProvider.notifier).setLocation(_locationCtrl.text);
    });
    _notesCtrl.addListener(() {
      ref.read(courseFormProvider.notifier).setNotes(_notesCtrl.text);
    });
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
              label: Text('周${AppConstants.weekdayLabels[i]}'),
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
        Wrap(
          spacing: 6,
          runSpacing: 4,
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
            TextButton(
              onPressed: () => ref
                  .read(courseFormProvider.notifier)
                  .setOddWeeks(totalWeeks),
              child: const Text('单周'),
            ),
            TextButton(
              onPressed: () => ref
                  .read(courseFormProvider.notifier)
                  .setEvenWeeks(totalWeeks),
              child: const Text('双周'),
            ),
            TextButton(
              onPressed: () => ref
                  .read(courseFormProvider.notifier)
                  .invertWeeks(totalWeeks),
              child: const Text('反选'),
            ),
          ],
        ),
        Row(
          children: [
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
          children: AppConstants.coursePalette.map((c) {
            final selected =
                AppConstants.courseDisplayColor(course.colorValue) == c;
            return InkWell(
              onTap: () {
                ref.read(courseFormProvider.notifier).setColor(c);
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(AppConstants.courseDisplayColor(
                    c,
                    dark: theme.brightness == Brightness.dark,
                  )),
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
        _PlatformSection(courseName: course.name.trim()),
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
            icon: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            label: Text('删除课程',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
      if (context.mounted) context.pop();
    }
  }
}

/// 「课程平台」区块：列表 + 添加/编辑/删除。改动随页面「保存」一起持久化。
class _PlatformSection extends ConsumerWidget {
  final String courseName;

  const _PlatformSection({required this.courseName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final platforms = ref.watch(coursePlatformsFormProvider);
    final notifier = ref.read(coursePlatformsFormProvider.notifier);

    Future<void> edit(int? index) async {
      final result = await showDialog<CoursePlatform>(
        context: context,
        builder: (_) => _CoursePlatformDialog(
          initial: index == null ? null : platforms[index],
        ),
      );
      if (result == null) return;
      if (index == null) {
        notifier.add(result);
      } else {
        notifier.replaceAt(index, result);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _FieldLabel('课程平台')),
            TextButton.icon(
              onPressed: () => edit(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加平台'),
            ),
          ],
        ),
        Text(
          courseName.isEmpty
              ? '本学期所有同名课程共享这些平台'
              : '本学期所有名为“$courseName”的课程共享这些平台',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < platforms.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(coursePlatformIcon(platforms[i].purpose)),
              title: Text(coursePlatformTitle(platforms[i])),
              subtitle: platforms[i].url == null
                  ? null
                  : Text(
                      platforms[i].url!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除平台',
                onPressed: () {
                  notifier.removeAt(i);
                },
              ),
              onTap: () => edit(i),
            ),
          ),
      ],
    );
  }
}

/// 新增与修改课程平台共用的弹窗：用途、平台名（必填）、链接（可选）。
class _CoursePlatformDialog extends StatefulWidget {
  final CoursePlatform? initial;
  const _CoursePlatformDialog({this.initial});

  @override
  State<_CoursePlatformDialog> createState() => _CoursePlatformDialogState();
}

class _CoursePlatformDialogState extends State<_CoursePlatformDialog> {
  late CoursePlatformPurpose _purpose =
      widget.initial?.purpose ?? CoursePlatformPurpose.onlineCourse;
  late final _nameCtrl = TextEditingController(text: widget.initial?.name);
  late final _urlCtrl = TextEditingController(text: widget.initial?.url);
  String? _nameError;
  String? _urlError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '请填写平台名');
      return;
    }
    final url = _urlCtrl.text.trim();
    if (url.isNotEmpty && !isAllowedPlatformUrl(url)) {
      setState(() => _urlError = '链接需为 http(s):// 开头的完整地址');
      return;
    }
    Navigator.of(context).pop(CoursePlatform(
      purpose: _purpose,
      name: name,
      url: url.isEmpty ? null : url,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '添加平台' : '编辑平台'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<CoursePlatformPurpose>(
              initialValue: _purpose,
              decoration: const InputDecoration(labelText: '用途'),
              items: [
                for (final purpose in CoursePlatformPurpose.values)
                  DropdownMenuItem(
                    value: purpose,
                    child: Row(
                      children: [
                        Icon(coursePlatformIcon(purpose), size: 20),
                        const SizedBox(width: 10),
                        Text(purpose.label),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _purpose = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: '平台名',
                hintText: '如：学习通',
                errorText: _nameError,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              decoration: InputDecoration(
                labelText: '链接（可选）',
                hintText: 'https://',
                errorText: _urlError,
              ),
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
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
                    sectionTime.startTime.isNotEmpty
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
