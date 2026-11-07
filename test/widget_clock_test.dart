import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:recess/core/constants/app_constants.dart';
import 'package:recess/core/models/course.dart';
import 'package:recess/core/models/semester.dart';
import 'package:recess/data/app_database.dart' as db;
import 'package:recess/data/providers/database_providers.dart';
import 'package:recess/features/settings/application/section_times_provider.dart';
import 'package:recess/features/widget/application/widget_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late db.AppDatabase database;
  late ProviderContainer container;
  late Map<String, Object?> saved;
  late Set<String> widgetNames;
  String? failingWidgetName;
  late DateTime now;
  const channel = MethodChannel('home_widget');
  const updates = MethodChannel('home_widget/updates');

  final semester = Semester(
    id: 's',
    name: '测试学期',
    startDate: DateTime(2026, 9, 7),
    totalWeeks: 3,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    saved = {};
    widgetNames = {};
    failingWidgetName = null;
    // 2026-09-17 是第 2 周周四。学期只跨 9 月，避免测试依赖运行机器的夏令时。
    now = DateTime(2026, 9, 17, 10, 0);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      final arguments = call.arguments as Map;
      if (call.method == 'saveWidgetData') {
        saved[arguments['id'] as String] = arguments['data'];
      } else if (call.method == 'updateWidget') {
        final name = arguments['android'] as String;
        widgetNames.add(name);
        if (name == failingWidgetName) {
          throw PlatformException(code: 'widget_update_failed');
        }
      }
      return true;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      updates,
      (call) async => null,
    );
    database = db.AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        widgetServiceProvider.overrideWith(
          (ref) => WidgetService(ref, now: () => now),
        ),
      ],
    );
    await container
        .read(semesterRepositoryProvider)
        .upsert(semester, activate: true);
    await container.read(sectionTimesProvider.notifier).setAllTimes(const {
      1: SectionTime('08:00', 45),
      2: SectionTime('08:55', 45),
    });
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(updates, null);
  });

  Course course(
    String name, {
    int dayOfWeek = 4,
    List<int> weeks = const [2],
    int startSection = 1,
    int endSection = 2,
    String? startTime,
    String? endTime,
    bool? useExplicitTimes,
    String? location,
    String? teacher,
    String? notes,
    int colorValue = AppConstants.defaultCourseColor,
  }) => Course(
    id: name,
    semesterId: 's',
    name: name,
    teacher: teacher,
    location: location,
    dayOfWeek: dayOfWeek,
    startSection: startSection,
    endSection: endSection,
    startTime: startTime,
    endTime: endTime,
    useExplicitTimes: useExplicitTimes ?? (startTime != null || endTime != null),
    weeks: weeks,
    colorValue: colorValue,
    notes: notes,
  );

  Future<void> upsertAndUpdate(List<Course> courses) async {
    for (final item in courses) {
      await container.read(courseRepositoryProvider).upsert(item);
    }
    await container.read(widgetServiceProvider).updateWidget();
  }

  List<Map<String, dynamic>> occurrences() =>
      (jsonDecode(saved['occurrences'] as String) as List)
          .cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> semesterDays() =>
      (jsonDecode(saved['semester_days'] as String) as List)
          .cast<Map<String, dynamic>>();

  Map<String, Map<String, dynamic>> occurrencesByName() => {
    for (final item in occurrences()) item['name'] as String: item,
  };

  test('写入从今天到学期结束的全部课次，不再写旧键', () async {
    await upsertAndUpdate([
      course('过去', weeks: const [1]),
      course('今天', location: '教1-101', teacher: '张老师', notes: '备注'),
      course('最后一周', weeks: const [3]),
      course('越界周', weeks: const [4]),
    ]);

    expect(saved.keys.toSet(), {
      'occurrences',
      'semester_days',
      'widget_loaded',
    });
    expect(saved['widget_loaded'], true);
    expect(widgetNames, {
      'CourseWidgetProvider',
      'CourseWidget3x2Provider',
      'CourseWidget2x3Provider',
      'CourseWidget4x2Provider',
      'CourseWidget4x4Provider',
    });

    final items = occurrences();
    expect(items.map((item) => item['name']), ['今天', '最后一周']);
    expect(items.map((item) => item['date']), ['2026-09-17', '2026-09-24']);

    final today = items.first;
    expect(today['start'], '2026-09-17T08:00');
    expect(today['end'], '2026-09-17T09:40');
    expect(today['start_section'], 1);
    expect(today['end_section'], 2);
    expect(today['location'], '教1-101');
    expect(
      today['color'],
      AppConstants.courseDisplayColor(AppConstants.defaultCourseColor),
    );
    expect(
      today['color_dark'],
      AppConstants.courseDisplayColor(
        AppConstants.defaultCourseColor,
        dark: true,
      ),
    );
    expect(today.keys, isNot(contains('teacher')));
    expect(today.keys, isNot(contains('notes')));
    expect(today.keys, isNot(contains('platforms')));

    final days = semesterDays();
    expect(days.first, {'date': '2026-09-17', 'week': 2});
    expect(days.last, {'date': '2026-09-27', 'week': 3});
    expect(
      days,
      hasLength(
        DateTime(2026, 9, 27).difference(DateTime(2026, 9, 17)).inDays + 1,
      ),
    );
    for (var i = 1; i < days.length; i++) {
      expect(
        DateTime.parse(
          days[i]['date'] as String,
        ).difference(DateTime.parse(days[i - 1]['date'] as String)).inDays,
        1,
      );
    }
  });

  test('一个尺寸刷新失败时仍通知其余尺寸', () async {
    failingWidgetName = 'CourseWidgetProvider';

    await upsertAndUpdate([course('今天')]);

    expect(widgetNames, {
      'CourseWidgetProvider',
      'CourseWidget3x2Provider',
      'CourseWidget2x3Provider',
      'CourseWidget4x2Provider',
      'CourseWidget4x4Provider',
    });
    expect(saved['widget_loaded'], true);
    expect(occurrencesByName(), contains('今天'));
  });

  test('课程自带钟点优先，缺失的一端回退到节次时间', () async {
    await upsertAndUpdate([
      course('显式', startTime: '08:30', endTime: '09:15'),
      course('无显式'),
      course('只开始', startTime: '08:30'),
      course('只结束', endTime: '09:15'),
    ]);

    final items = occurrencesByName();
    expect(items['显式']!['start'], '2026-09-17T08:30');
    expect(items['显式']!['end'], '2026-09-17T09:15');
    expect(items['无显式']!['start'], '2026-09-17T08:00');
    expect(items['无显式']!['end'], '2026-09-17T09:40');
    expect(items['只开始']!['start'], '2026-09-17T08:30');
    expect(items['只开始']!['end'], '2026-09-17T09:40');
    expect(items['只结束']!['start'], '2026-09-17T08:00');
    expect(items['只结束']!['end'], '2026-09-17T09:15');
  });

  test('两端都拿不到钟点时写入空字符串，无效显式值不回退', () async {
    await upsertAndUpdate([
      course('缺节次', startSection: 15, endSection: 16),
      course('空开始', startTime: ''),
      course('坏结束', endTime: '不是钟点'),
    ]);

    final items = occurrencesByName();
    expect(items['缺节次']!['start'], '');
    expect(items['缺节次']!['end'], '');
    expect(items['空开始']!['start'], '');
    expect(items['空开始']!['end'], '2026-09-17T09:40');
    expect(items['坏结束']!['start'], '2026-09-17T08:00');
    expect(items['坏结束']!['end'], '');
  });

  test('节次时间变更后回退钟点跟随更新，显式快照保持原值', () async {
    await container
        .read(courseRepositoryProvider)
        .upsert(course('显式快照', startTime: '08:00', endTime: '09:40'));
    await container.read(courseRepositoryProvider).upsert(course('节次回退'));
    await container
        .read(sectionTimesProvider.notifier)
        .applyTemplate(sectionTimeTemplates[1]);

    await container.read(widgetServiceProvider).updateWidget();

    final items = occurrencesByName();
    expect(items['显式快照']!['start'], '2026-09-17T08:00');
    expect(items['显式快照']!['end'], '2026-09-17T09:40');
    expect(items['节次回退']!['start'], '2026-09-17T08:00');
    expect(items['节次回退']!['end'], '2026-09-17T11:15');
  });

  test('手动当前周让未来日期都使用同一周，并按日期写入课次', () async {
    await container
        .read(semesterRepositoryProvider)
        .upsert(semester.copyWith(currentWeekOverride: 3), activate: true);
    await upsertAndUpdate([
      course('重复课', weeks: const [3]),
    ]);

    final days = semesterDays();
    expect(days, isNotEmpty);
    expect(days.map((day) => day['week']).toSet(), {3});
    expect(occurrences().map((item) => item['date']), [
      '2026-09-17',
      '2026-09-24',
    ]);
    expect(occurrences().map((item) => item['name']), ['重复课', '重复课']);
  });

  test('开学前写入今天到学期结束的逐日映射与开课后课次', () async {
    now = DateTime(2026, 8, 1, 9, 0);
    await upsertAndUpdate([
      course('第一节课', dayOfWeek: 1, weeks: const [1]),
    ]);

    final days = semesterDays();
    expect(days.first, {'date': '2026-08-01', 'week': 0});
    expect(days.last, {'date': '2026-09-27', 'week': 3});
    expect(days.firstWhere((day) => day['date'] == '2026-09-07')['week'], 1);
    expect(occurrencesByName()['第一节课']!['date'], '2026-09-07');
  });

  test('学期结束后不写课次，但仍标记已加载', () async {
    now = DateTime(2026, 10, 1, 9, 0);
    await upsertAndUpdate([course('已结束')]);

    expect(jsonDecode(saved['occurrences'] as String), isEmpty);
    expect(jsonDecode(saved['semester_days'] as String), isEmpty);
    expect(saved['widget_loaded'], true);
    expect(widgetNames, contains('CourseWidgetProvider'));
  });

  test('时间冲突的课次全部保留，按开始时刻、节次与名称稳定排序', () async {
    await upsertAndUpdate([
      course('晚间', startTime: '10:00', startSection: 3, endSection: 4),
      course('早五', startTime: '08:00', startSection: 5, endSection: 6),
      course('早一', startTime: '08:00', startSection: 1, endSection: 2),
      course('冲突B', startTime: '09:00'),
      course('冲突A', startTime: '09:00'),
      course('无钟点后', startSection: 11, endSection: 12),
      course('无钟点前', startSection: 9, endSection: 10),
    ]);

    expect(occurrences().map((item) => item['name']), [
      '早一',
      '早五',
      '冲突A',
      '冲突B',
      '晚间',
      '无钟点前',
      '无钟点后',
    ]);
  });
}
