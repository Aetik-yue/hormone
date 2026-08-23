import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/core/models/course.dart';
import 'package:hormone/data/app_database.dart' as db;
import 'package:hormone/data/repositories/course_repository.dart';

void main() {
  late db.AppDatabase database;
  late CourseRepository repository;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = CourseRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('导入新课表会完整替换当前学期课程并保留其他学期', () async {
    await repository.upsert(_course('old-a', 'semester-a', '旧课程 A'));
    await repository.upsert(_course('old-b', 'semester-a', '旧课程 B'));
    await repository.upsert(_course('other', 'semester-b', '其他学期课程'));

    await repository.replaceForSemester('semester-a', [
      _course('new-a', 'semester-a', '新课程 A'),
      _course('new-b', 'semester-a', '新课程 B'),
    ]);

    final current = await repository.getCourses('semester-a');
    expect(current.map((course) => course.id),
        unorderedEquals(['new-a', 'new-b']));
    expect(current.map((course) => course.name),
        unorderedEquals(['新课程 A', '新课程 B']));

    final other = await repository.getCourses('semester-b');
    expect(other, hasLength(1));
    expect(other.single.id, 'other');
  });

  test('空替换列表只会清空指定学期', () async {
    await repository.upsert(_course('old-a', 'semester-a', '旧课程'));
    await repository.upsert(_course('other', 'semester-b', '其他学期课程'));

    await repository.replaceForSemester('semester-a', const []);

    expect(await repository.getCourses('semester-a'), isEmpty);
    expect(await repository.getCourses('semester-b'), hasLength(1));
  });

  test('替换数据不属于目标学期时保留原课表', () async {
    await repository.upsert(_course('old-a', 'semester-a', '旧课程'));

    await expectLater(
      repository.replaceForSemester('semester-a', [
        _course('wrong', 'semester-b', '错误学期课程'),
      ]),
      throwsArgumentError,
    );

    final current = await repository.getCourses('semester-a');
    expect(current, hasLength(1));
    expect(current.single.id, 'old-a');
  });
}

Course _course(String id, String semesterId, String name) => Course(
      id: id,
      semesterId: semesterId,
      name: name,
      dayOfWeek: DateTime.monday,
      startSection: 1,
      endSection: 2,
      weeks: const [1, 2, 3],
    );
