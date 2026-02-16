import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/core/models/task.dart';

void main() {
  group('HabitRecurrence', () {
    test('specificDays defaults to Monday when empty', () {
      final recurrence = HabitRecurrence.specificDays(const <int>[]);

      expect(recurrence.type, HabitRecurrenceType.specificDays);
      expect(recurrence.daysOfWeek, const <int>[DateTime.monday]);
      expect(recurrence.label, 'Mon');
    });

    test('legacy weekly string maps to provided weekday', () {
      final recurrence = HabitRecurrence.fromJson(
        'weekly',
        legacyWeeklyWeekday: DateTime.friday,
      );

      expect(recurrence.type, HabitRecurrenceType.specificDays);
      expect(recurrence.daysOfWeek, const <int>[DateTime.friday]);
      expect(recurrence.label, 'Fri');
    });

    test('timesPerWeek is clamped to valid range', () {
      final low = HabitRecurrence.timesPerWeek(0);
      final high = HabitRecurrence.timesPerWeek(99);

      expect(low.timesPerWeek, 1);
      expect(high.timesPerWeek, 7);
    });
  });

  test('TaskItem json roundtrip preserves recurrence object', () {
    final original = TaskItem(
      id: 't-1',
      title: 'Workout',
      type: TaskType.habit,
      completed: false,
      createdAt: DateTime(2026, 2, 17),
      recurrence: HabitRecurrence.timesPerWeek(3),
    );

    final roundTrip = TaskItem.fromJson(original.toJson());

    expect(roundTrip.recurrence?.type, HabitRecurrenceType.timesPerWeek);
    expect(roundTrip.recurrence?.timesPerWeek, 3);
    expect(roundTrip.title, original.title);
  });
}
