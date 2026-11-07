import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recess/core/models/course.dart';
import 'package:recess/core/models/course_platform.dart';
import 'package:recess/data/app_database.dart' as db;
import 'package:recess/data/repositories/course_platform_repository.dart';
import 'package:recess/data/repositories/course_repository.dart';

void main() {
  late db.AppDatabase database;
  late CoursePlatformRepository platforms;
  late CourseRepository courses;

  const xuexitong = CoursePlatform(
    purpose: CoursePlatformPurpose.onlineCourse,
    name: '学习通',
    url: 'https://mooc1.chaoxing.com',
  );
  const qqGroup = CoursePlatform(
    purpose: CoursePlatformPurpose.group,
    name: 'QQ 群 726xxxx31',
  );
  const educoder = CoursePlatform(
    purpose: CoursePlatformPurpose.lab,
    name: '头歌',
  );

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    platforms = CoursePlatformRepository(database);
    courses = CourseRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('整体替换某门课的平台后按原顺序读回', () async {
    await platforms.replacePlatforms('s1', '操作系统', [xuexitong, qqGroup]);
    expect(await platforms.getPlatforms('s1', '操作系统'), [xuexitong, qqGroup]);

    await platforms.replacePlatforms('s1', '操作系统', [qqGroup]);
    expect(await platforms.getPlatforms('s1', '操作系统'), [qqGroup]);
  });

  test('课程名 trim 后精确匹配，且按学期隔离', () async {
    await platforms.replacePlatforms('s1', ' 操作系统 ', [xuexitong]);
    await platforms.replacePlatforms('s2', '操作系统', [educoder]);

    expect(await platforms.getPlatforms('s1', '操作系统'), [xuexitong]);
    expect(await platforms.getPlatforms('s1', '操作系统实验'), isEmpty);
    expect(await platforms.getPlatforms('s2', '操作系统'), [educoder]);
  });

  test('监听某门课的平台会随替换发出新列表', () async {
    final stream = platforms.watchPlatforms('s1', '操作系统');
    final expectation = expectLater(
      stream,
      emitsInOrder([
        isEmpty,
        [xuexitong],
      ]),
    );
    await Future<void>.delayed(Duration.zero);
    await platforms.replacePlatforms('s1', '操作系统', [xuexitong]);
    await expectation;
  });

  test('按学期取出全部平台，以课程名分组', () async {
    await platforms.replacePlatforms('s1', '操作系统', [xuexitong, qqGroup]);
    await platforms.replacePlatforms('s1', '操作系统实验', [educoder]);
    await platforms.replacePlatforms('s2', '其他课', [educoder]);

    expect(await platforms.getPlatformsBySemester('s1'), {
      '操作系统': [xuexitong, qqGroup],
      '操作系统实验': [educoder],
    });
  });

  group('改名迁移', () {
    test('新名下没有平台时复制过去；旧名已无课程使用则删除旧名下的平台',
        () async {
      await courses.upsert(_course('c1', '操作系统新'));
      await platforms.replacePlatforms('s1', '操作系统', [xuexitong]);

      await platforms.migrateOnRename('s1', from: '操作系统', to: '操作系统新');

      expect(await platforms.getPlatforms('s1', '操作系统新'), [xuexitong]);
      expect(await platforms.getPlatforms('s1', '操作系统'), isEmpty);
    });

    test('本学期还有其他课程使用旧名时保留旧名下的平台', () async {
      await courses.upsert(_course('c1', '操作系统新'));
      await courses.upsert(_course('c2', '操作系统'));
      await platforms.replacePlatforms('s1', '操作系统', [xuexitong]);

      await platforms.migrateOnRename('s1', from: '操作系统', to: '操作系统新');

      expect(await platforms.getPlatforms('s1', '操作系统新'), [xuexitong]);
      expect(await platforms.getPlatforms('s1', '操作系统'), [xuexitong]);
    });

    test('新名下已有平台时不覆盖', () async {
      await courses.upsert(_course('c1', '操作系统实验'));
      await platforms.replacePlatforms('s1', '操作系统', [xuexitong]);
      await platforms.replacePlatforms('s1', '操作系统实验', [educoder]);

      await platforms.migrateOnRename('s1', from: '操作系统', to: '操作系统实验');

      expect(await platforms.getPlatforms('s1', '操作系统实验'), [educoder]);
    });

    test('课程名只差首尾空格时不算改名', () async {
      await courses.upsert(_course('c1', '操作系统 '));
      await platforms.replacePlatforms('s1', '操作系统', [xuexitong]);

      await platforms.migrateOnRename('s1', from: '操作系统', to: '操作系统 ');

      expect(await platforms.getPlatforms('s1', '操作系统'), [xuexitong]);
    });
  });

  test('导入替换课程时不删除平台，同名课程重新对上', () async {
    await courses.upsert(_course('old', '操作系统'));
    await platforms.replacePlatforms('s1', '操作系统', [xuexitong]);

    await courses.replaceForSemester('s1', [_course('new', '操作系统')]);

    expect(await platforms.getPlatforms('s1', '操作系统'), [xuexitong]);
  });
}

Course _course(String id, String name) => Course(
      id: id,
      semesterId: 's1',
      name: name,
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      weeks: const [1],
    );
