import 'package:flutter_test/flutter_test.dart';
import 'package:hormone/features/settings/domain/section_time.dart';
import 'package:hormone/features/settings/domain/section_time_shift.dart';

void main() {
  const times = {
    1: SectionTime('08:00', 45),
    2: SectionTime('08:55', 50),
    3: SectionTime('10:00', 45),
    5: SectionTime('14:00', 90),
    9: SectionTime('19:00', 45),
    12: SectionTime('21:45', 45),
    13: SectionTime('', 60),
  };

  test('延后第一节时保留不同课长、课间及午晚休间隔', () {
    final shifted = shiftSectionTimes(times, '08:30');

    expect(shifted[1]?.timeRange, '08:30-09:15');
    expect(shifted[2]?.timeRange, '09:25-10:15');
    expect(shifted[3]?.startTime, '10:30');
    expect(shifted[5]?.timeRange, '14:30-16:00');
    expect(shifted[9]?.startTime, '19:30');
    expect(shifted[12]?.timeRange, '22:15-23:00');
    expect(shifted[13]?.startTime, isEmpty);
    expect(shifted[13]?.durationMinutes, 60);
    expect(shifted.keys, times.keys);
    expect(times[1]?.startTime, '08:00');
  });

  test('提前和连续修改均相对当前时间表计算，不累加旧偏移', () {
    final earlier = shiftSectionTimes(times, '07:30');
    expect(earlier[2]?.startTime, '08:25');
    expect(earlier[12]?.endTime, '22:00');
    final restored = shiftSectionTimes(earlier, '08:00');
    for (final section in times.keys) {
      expect(restored[section]?.timeRange, times[section]?.timeRange);
    }
  });

  test('兼容历史单数字小时格式和零偏移', () {
    final shifted = shiftSectionTimes({
      1: const SectionTime('7:30', 45),
    }, '07:30');
    expect(shifted[1]?.timeRange, '07:30-08:15');
  });

  test('最后一节恰好在午夜结束可以保存', () {
    final shifted = shiftSectionTimes(times, '09:30');
    expect(shifted[12]?.timeRange, '23:15-00:00');
  });

  test('课程开始或结束超出当天时拒绝整批修改', () {
    for (final firstStart in ['09:31', '23:59']) {
      expect(
        () => shiftSectionTimes(times, firstStart),
        throwsA(isA<SectionTimeShiftException>()),
      );
      expect(times[1]?.startTime, '08:00');
    }
    // 历史配置也可能把后续节次设得比第一节早，不能回绕到前一天。
    expect(
      () => shiftSectionTimes({
        1: const SectionTime('08:00', 45),
        2: const SectionTime('00:15', 45),
      }, '07:30'),
      throwsA(isA<SectionTimeShiftException>()),
    );
  });

  test('第一节未设置或有损坏时间时返回明确错误', () {
    for (final bad in ['', '24:00', '08:60', 'invalid']) {
      expect(
        () => shiftSectionTimes(times, bad),
        throwsA(isA<SectionTimeShiftException>()),
      );
      expect(
        () => shiftSectionTimes({1: SectionTime(bad, 45)}, '08:30'),
        throwsA(isA<SectionTimeShiftException>()),
      );
    }
    expect(
      () => shiftSectionTimes({
        ...times,
        2: const SectionTime('08:55', 0),
      }, '08:30'),
      throwsA(isA<SectionTimeShiftException>()),
    );
  });
}
