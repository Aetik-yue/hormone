import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/features/schedule/domain/schedule_helpers.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';

/// 课程搜索：按名称/教师/教室模糊匹配激活学期全部课程。
/// 返回选中课程（null 表示取消搜索），由调用方决定后续动作。
class CourseSearchDelegate extends SearchDelegate<Course?> {
  final WidgetRef _ref;

  CourseSearchDelegate(this._ref);

  @override
  String get searchFieldLabel => '搜索课程名称 / 教师 / 教室';

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: '清空',
            onPressed: () {
              query = '';
              showSuggestions(context);
            },
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '返回',
        onPressed: () => close(context, null),
      );

  List<Course> _results() {
    final courses =
        _ref.read(scheduleCoursesProvider).value ?? const <Course>[];
    return filterCourses(courses, query);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      return const _EmptyHint(text: '输入关键词搜索课程');
    }
    final results = _results();
    if (results.isEmpty) return const _EmptyHint(text: '没有匹配的课程');
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) => _ResultTile(
        course: results[i],
        onTap: () => close(context, results[i]),
      ),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().isEmpty) {
      return const _EmptyHint(text: '输入关键词搜索课程');
    }
    final results = _results();
    if (results.isEmpty) return const _EmptyHint(text: '没有匹配的课程');
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) => _ResultTile(
        course: results[i],
        onTap: () => close(context, results[i]),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final Course course;
  final VoidCallback onTap;

  const _ResultTile({required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: Color(course.colorValue),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(course.name),
      subtitle: Text(
        [
          '周${_dayLabels[course.dayOfWeek - 1]} 第${course.startSection}-${course.endSection}节',
          if (course.teacher != null && course.teacher!.isNotEmpty)
            course.teacher!,
          if (course.location != null && course.location!.isNotEmpty)
            course.location!,
        ].join(' · '),
        style: theme.textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

const _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(text,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}