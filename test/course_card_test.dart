import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/features/schedule/presentation/week_view.dart';

void main() {
  const course = Course(
    id: 'course-card-test',
    semesterId: 'semester',
    name: '云计算与大数据',
    teacher: '张老师',
    location: 'D101',
    dayOfWeek: 1,
    startSection: 1,
    endSection: 2,
    colorValue: 0xFF5B8DEF,
  );

  testWidgets('窄课程卡片优先给课程名更多行数且不会溢出', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 42,
              height: 104,
              child: CourseCard(
                course: course,
                onTap: _noop,
                onLongPress: _noop,
              ),
            ),
          ),
        ),
      ),
    );

    final name = tester.widget<Text>(
      find.byKey(const Key('course-card-name')),
    );
    expect(name.data, course.name);
    expect(name.maxLines, 4);
    expect(name.style?.fontSize, 10.5);
    expect(find.byKey(const Key('course-card-color-rail')), findsOneWidget);
    expect(find.byKey(const Key('course-card-location')), findsOneWidget);
    expect(find.byKey(const Key('course-card-teacher')), findsOneWidget);
    expect(find.text('D101'), findsOneWidget);
    expect(find.text('张老师'), findsOneWidget);
    expect(
      find.bySemanticsLabel('云计算与大数据，周一，第1到2节，D101，张老师'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    semantics.dispose();
  });

  testWidgets('单节课卡片隐藏地点和教师以保证课程名可读', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 42,
              height: 48,
              child: CourseCard(
                course: course,
                onTap: _noop,
                onLongPress: _noop,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('course-card-name')), findsOneWidget);
    expect(find.byKey(const Key('course-card-location')), findsNothing);
    expect(find.byKey(const Key('course-card-teacher')), findsNothing);
    expect(find.text('D101'), findsNothing);
    expect(find.text('张老师'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('课程色板上的前景色对比度不低于 4.5:1', () {
    const palette = [
      Color(0xFF5B8DEF),
      Color(0xFF3FBFA8),
      Color(0xFFF2A25C),
      Color(0xFF9B8AFB),
      Color(0xFFEF6E8D),
      Color(0xFF4FA3E3),
      Color(0xFFE8BE50),
      Color(0xFF63C98D),
      Color(0xFFC08CE8),
      Color(0xFFF08C7C),
    ];

    for (final background in palette) {
      final foreground = courseCardForegroundColor(background);
      expect(
        _contrastRatio(foreground, background),
        greaterThanOrEqualTo(4.5),
        reason: '${background.toARGB32().toRadixString(16)} 上的课程文字对比度不足',
      );
    }
  });

  test('低饱和卡面在浅色和深色主题下保持文字对比度', () {
    const accent = Color(0xFF5B8DEF);

    for (final brightness in Brightness.values) {
      final scheme = ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
      );
      final surface = courseCardSurfaceColor(accent, scheme, brightness);
      final foreground = courseCardForegroundColor(surface);

      expect(surface, isNot(accent));
      expect(surface, isNot(scheme.surface));
      expect(
        _contrastRatio(foreground, surface),
        greaterThanOrEqualTo(4.5),
        reason: '$brightness 主题下的课程文字对比度不足',
      );
    }
  });
}

void _noop() {}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
