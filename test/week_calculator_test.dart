import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/core/utils/week_calculator.dart';

void main() {
  // 2024-09-02 是周一。
  final monday = DateTime(2024, 9, 2);

  group('computeCurrentWeek', () {
    test('开学当天为第 1 周', () {
      expect(computeCurrentWeek(monday, monday), 1);
    });

    test('恰好一周后为第 2 周', () {
      expect(computeCurrentWeek(monday, monday.add(const Duration(days: 7))), 2);
    });

    test('两周后为第 3 周', () {
      expect(
          computeCurrentWeek(monday, monday.add(const Duration(days: 14))), 3);
    });

    test('早于开学返回 0', () {
      expect(
          computeCurrentWeek(monday, monday.subtract(const Duration(days: 1))),
          0);
    });
  });

  group('dateForWeekday', () {
    test('第1周周一 = 开学日', () {
      expect(dateForWeekday(monday, 1, 1), DateTime(2024, 9, 2));
    });

    test('第1周周三 = 开学日+2', () {
      expect(dateForWeekday(monday, 1, 3), DateTime(2024, 9, 4));
    });

    test('第2周周一 = 开学日+7', () {
      expect(dateForWeekday(monday, 2, 1), DateTime(2024, 9, 9));
    });
  });

  group('courseOnWeek', () {
    test('周次包含时为真', () {
      expect(courseOnWeek([1, 3, 5, 7], 3), isTrue);
    });
    test('周次不包含时为假', () {
      expect(courseOnWeek([1, 3, 5, 7], 2), isFalse);
    });
    test('空周次永远为假', () {
      expect(courseOnWeek(const [], 1), isFalse);
    });
  });
}
