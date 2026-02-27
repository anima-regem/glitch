import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/core/models/app_data.dart';
import 'package:glitch/core/models/app_preferences.dart';
import 'package:glitch/core/models/task.dart';
import 'package:glitch/core/services/backup_service.dart';
import 'package:glitch/core/services/reminder_service.dart';
import 'package:glitch/core/storage/local_store.dart';
import 'package:glitch/shared/state/app_controller.dart';

class _MemoryStore implements LocalStore {
  _MemoryStore({AppData? initialData}) : _data = initialData ?? AppData.empty();

  AppData _data;

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

class _RecordingBackupService extends BackupService {
  _RecordingBackupService({this.shouldThrow = false});

  final bool shouldThrow;
  int writeCalls = 0;

  @override
  Future<String?> writeVaultSnapshot({
    required AppData data,
    required String directoryPath,
  }) async {
    writeCalls += 1;
    if (shouldThrow) {
      throw StateError('disk offline');
    }
    return '$directoryPath/glitch-vault-latest.json';
  }
}

class _RecordingReminderService implements ReminderService {
  int scheduleCalls = 0;
  int cancelCalls = 0;
  int testNotificationCalls = 0;
  bool testNotificationResult = true;
  int? lastHour;
  int? lastMinute;

  @override
  Future<void> cancelReminder() async {
    cancelCalls += 1;
  }

  @override
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    required String title,
    required String body,
    Set<int>? weekdays,
    int? dayInterval,
  }) async {
    scheduleCalls += 1;
    lastHour = hour;
    lastMinute = minute;
  }

  @override
  Future<bool> showTestNotification({
    required String title,
    required String body,
  }) async {
    testNotificationCalls += 1;
    return testNotificationResult;
  }

  void reset() {
    scheduleCalls = 0;
    cancelCalls = 0;
    testNotificationCalls = 0;
    lastHour = null;
    lastMinute = null;
  }
}

ProviderContainer _containerWithMemoryStore({
  AppData? initialData,
  BackupService? backupService,
  ReminderService? reminderService,
}) {
  return ProviderContainer(
    overrides: <Override>[
      localStoreProvider.overrideWithValue(
        _MemoryStore(initialData: initialData),
      ),
      if (backupService != null)
        backupServiceProvider.overrideWithValue(backupService),
      if (reminderService != null)
        reminderServiceProvider.overrideWithValue(reminderService),
    ],
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

  test(
    'unscheduled chores do not inflate day progress planned count',
    () async {
      final container = _containerWithMemoryStore();
      addTearDown(container.dispose);

      await container.read(appControllerProvider.future);
      final notifier = container.read(appControllerProvider.notifier);
      final today = DateTime.now();

      await notifier.addTask(
        title: 'Unscheduled backlog item',
        type: TaskType.chore,
        scheduledDate: null,
      );

      final progress = notifier.dayProgress(today);
      expect(progress.plannedCount, 0);
      expect(progress.completedCount, 0);
    },
  );

  test('dayProgress stays stable for past day after future changes', () async {
    final container = _containerWithMemoryStore();
    addTearDown(container.dispose);

    await container.read(appControllerProvider.future);
    final notifier = container.read(appControllerProvider.notifier);

    final targetDay = DateTime.now().subtract(const Duration(days: 2));
    final futureDay = DateTime.now().add(const Duration(days: 3));

    await notifier.addTask(
      title: 'Past task',
      type: TaskType.chore,
      scheduledDate: targetDay,
    );

    final taskId = container.read(appControllerProvider).value!.tasks.single.id;
    await notifier.completeTask(taskId);

    final before = notifier.dayProgress(targetDay);

    await notifier.addTask(
      title: 'Future task',
      type: TaskType.chore,
      scheduledDate: futureDay,
    );

    final after = notifier.dayProgress(targetDay);
    expect(after.plannedCount, before.plannedCount);
    expect(after.completedCount, before.completedCount);
  });

  test('updateTaskDuration never decreases stored duration', () async {
    final container = _containerWithMemoryStore();
    addTearDown(container.dispose);

    await container.read(appControllerProvider.future);
    final notifier = container.read(appControllerProvider.notifier);
    final today = DateTime.now();

    await notifier.addTask(
      title: 'Task One',
      type: TaskType.chore,
      scheduledDate: today,
    );
    final taskId = container.read(appControllerProvider).value!.tasks.single.id;
    await notifier.updateTaskDuration(taskId, 5);
    await notifier.updateTaskDuration(taskId, 2);

    final appData = container.read(appControllerProvider).value!;
    final task = appData.tasks.firstWhere((item) => item.id == taskId);
    expect(task.actualMinutes, 5);
  });

  test('vault sync is debounced across rapid saves', () async {
    final backupService = _RecordingBackupService();
    final initialData = AppData.empty().copyWith(
      preferences: AppPreferences.defaults().copyWith(
        backupVaultPath: '/vault',
        backupVaultPromptDismissed: true,
      ),
    );
    final container = _containerWithMemoryStore(
      initialData: initialData,
      backupService: backupService,
    );
    addTearDown(container.dispose);

    await container.read(appControllerProvider.future);
    final notifier = container.read(appControllerProvider.notifier);

    await notifier.addTask(
      title: 'Task 1',
      type: TaskType.chore,
      scheduledDate: DateTime.now(),
    );
    await notifier.addTask(
      title: 'Task 2',
      type: TaskType.chore,
      scheduledDate: DateTime.now(),
    );

    await Future<void>.delayed(const Duration(milliseconds: 2300));

    expect(backupService.writeCalls, 1);
  });

  test(
    'vault sync failure sets status but does not block local save',
    () async {
      final backupService = _RecordingBackupService(shouldThrow: true);
      final initialData = AppData.empty().copyWith(
        preferences: AppPreferences.defaults().copyWith(
          backupVaultPath: '/vault',
          backupVaultPromptDismissed: true,
        ),
      );
      final container = _containerWithMemoryStore(
        initialData: initialData,
        backupService: backupService,
      );
      addTearDown(container.dispose);

      await container.read(appControllerProvider.future);
      final notifier = container.read(appControllerProvider.notifier);

      await notifier.addTask(
        title: 'Task with failing sync',
        type: TaskType.chore,
        scheduledDate: DateTime.now(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 2300));

      final appData = container.read(appControllerProvider).value!;
      expect(appData.tasks.length, 1);
      expect(appData.preferences.lastVaultSyncError, contains('disk offline'));
    },
  );

  test(
    'reminder settings schedule and cancel reminders appropriately',
    () async {
      final reminderService = _RecordingReminderService();
      final container = _containerWithMemoryStore(
        reminderService: reminderService,
      );
      addTearDown(container.dispose);

      await container.read(appControllerProvider.future);
      reminderService.reset();
      final notifier = container.read(appControllerProvider.notifier);

      await notifier.setRemindersEnabled(true);
      expect(reminderService.scheduleCalls, 1);
      expect(reminderService.cancelCalls, 0);

      await notifier.setReminderTime(hour: 9, minute: 15);
      expect(reminderService.scheduleCalls, 2);
      expect(reminderService.lastHour, 9);
      expect(reminderService.lastMinute, 15);

      await notifier.setRemindersEnabled(false);
      expect(reminderService.cancelCalls, 1);
    },
  );

  test(
    'voice typing preferences persist through app controller setters',
    () async {
      final container = _containerWithMemoryStore();
      addTearDown(container.dispose);

      await container.read(appControllerProvider.future);
      final notifier = container.read(appControllerProvider.notifier);

      await notifier.setVoiceTypingEnabled(false);
      await notifier.setVoiceTypingAllowNetworkFallback(true);
      await notifier.setVoiceTypingOnDeviceModelBetaEnabled(true);
      await notifier.setVoiceTypingModelInstallation(
        modelId: 'standard',
        modelVersion: '2023-02-17',
        installedAt: DateTime(2026, 2, 25, 17, 10),
      );

      final prefs = container.read(appControllerProvider).value!.preferences;
      expect(prefs.voiceTypingEnabled, isFalse);
      expect(prefs.voiceTypingAllowNetworkFallback, isTrue);
      expect(prefs.voiceTypingOnDeviceModelBetaEnabled, isTrue);
      expect(prefs.voiceTypingModelId, 'standard');
      expect(prefs.voiceTypingModelVersion, '2023-02-17');
      expect(prefs.voiceTypingModelInstalledAt, DateTime(2026, 2, 25, 17, 10));

      await notifier.setVoiceTypingModelSelection('ultra_full');
      final selected = container.read(appControllerProvider).value!.preferences;
      expect(selected.voiceTypingModelId, 'ultra_full');
      expect(selected.voiceTypingModelVersion, '2023-02-17');
      expect(
        selected.voiceTypingModelInstalledAt,
        DateTime(2026, 2, 25, 17, 10),
      );

      await notifier.clearVoiceTypingModelInstallMetadata();
      final metadataCleared = container
          .read(appControllerProvider)
          .value!
          .preferences;
      expect(metadataCleared.voiceTypingModelId, 'ultra_full');
      expect(metadataCleared.voiceTypingModelVersion, isNull);
      expect(metadataCleared.voiceTypingModelInstalledAt, isNull);

      await notifier.clearVoiceTypingModelInstallation();
      final fullyCleared = container
          .read(appControllerProvider)
          .value!
          .preferences;
      expect(fullyCleared.voiceTypingModelId, isNull);
      expect(fullyCleared.voiceTypingModelVersion, isNull);
      expect(fullyCleared.voiceTypingModelInstalledAt, isNull);
    },
  );

  test('test reminder triggers reminder service test notification', () async {
    final reminderService = _RecordingReminderService();
    final container = _containerWithMemoryStore(
      reminderService: reminderService,
    );
    addTearDown(container.dispose);

    await container.read(appControllerProvider.future);
    final notifier = container.read(appControllerProvider.notifier);

    final success = await notifier.sendTestReminderNotification();

    expect(success, isTrue);
    expect(reminderService.testNotificationCalls, 1);
  });
}
