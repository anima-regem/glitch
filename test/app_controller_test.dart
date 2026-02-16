import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/core/models/app_data.dart';
import 'package:glitch/core/models/task.dart';
import 'package:glitch/core/storage/local_store.dart';
import 'package:glitch/shared/state/app_controller.dart';

class _MemoryStore implements LocalStore {
  AppData _data = AppData.empty();

  @override
  Future<AppData> load() async => _data;

  @override
  Future<void> overwrite(AppData data) async {
    _data = data;
  }

  @override
  Future<void> save(AppData data) async {
    _data = data;
  }
}

ProviderContainer _containerWithMemoryStore() {
  return ProviderContainer(
    overrides: <Override>[localStoreProvider.overrideWithValue(_MemoryStore())],
  );
}

void main() {
  test('timesPerWeek habit is hidden after weekly target is met', () async {
    final container = _containerWithMemoryStore();
    addTearDown(container.dispose);

    await container.read(appControllerProvider.future);
    final notifier = container.read(appControllerProvider.notifier);

    await notifier.addTask(
      title: 'Workout',
      type: TaskType.habit,
      recurrence: HabitRecurrence.timesPerWeek(1),
    );

    final habit = notifier.allHabits().single;
    final today = DateTime.now();

    expect(
      notifier.todayTasks(today).any((task) => task.id == habit.id),
      isTrue,
    );

    await notifier.completeHabitOnDate(taskId: habit.id, date: today);

    expect(notifier.habitCompletionsThisWeek(habit.id), 1);
    expect(notifier.habitWeeklyTarget(habit.id), 1);
    expect(
      notifier.todayTasks(today).any((task) => task.id == habit.id),
      isFalse,
    );
  });

  test('reopenTask reverses perfect-day status', () async {
    final container = _containerWithMemoryStore();
    addTearDown(container.dispose);

    await container.read(appControllerProvider.future);
    final notifier = container.read(appControllerProvider.notifier);
    final today = DateTime.now();

    await notifier.addTask(
      title: 'Take out trash',
      type: TaskType.chore,
      scheduledDate: today,
    );

    final taskId = container.read(appControllerProvider).value!.tasks.single.id;

    await notifier.completeTask(taskId);
    final before = notifier.dayProgress(today);

    expect(before.plannedCount, 1);
    expect(before.completedCount, 1);
    expect(before.isPerfectDay, isTrue);

    await notifier.reopenTask(taskId);
    final after = notifier.dayProgress(today);

    expect(after.plannedCount, 1);
    expect(after.completedCount, 0);
    expect(after.isPerfectDay, isFalse);
  });

  test('undoHabitCompletion removes completion log for that day', () async {
    final container = _containerWithMemoryStore();
    addTearDown(container.dispose);

    await container.read(appControllerProvider.future);
    final notifier = container.read(appControllerProvider.notifier);
    final date = DateTime.now();

    await notifier.addTask(
      title: 'Journal',
      type: TaskType.habit,
      recurrence: HabitRecurrence.daily(),
    );

    final habitId = notifier.allHabits().single.id;

    await notifier.completeHabitOnDate(taskId: habitId, date: date);
    expect(notifier.isHabitCompletedOnDate(habitId, date), isTrue);

    await notifier.undoHabitCompletion(taskId: habitId, date: date);
    expect(notifier.isHabitCompletedOnDate(habitId, date), isFalse);
  });
}
