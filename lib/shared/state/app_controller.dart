import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/app_data.dart';
import '../../core/models/app_preferences.dart';
import '../../core/models/habit_log.dart';
import '../../core/models/project.dart';
import '../../core/models/task.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/reminder_service.dart';
import '../../core/services/voice_typing_service.dart';
import '../../core/storage/local_store.dart';
import '../../core/utils/date_time_utils.dart';

final localStoreProvider = Provider<LocalStore>((ref) => HiveLocalStore());

final backupServiceProvider = Provider<BackupService>((ref) => BackupService());

final reminderServiceProvider = Provider<ReminderService>(
  (ref) => const NoopReminderService(),
);

final voiceTypingServiceProvider = Provider<VoiceTypingService>(
  (ref) => NativeVoiceTypingService(),
);

final appControllerProvider = AsyncNotifierProvider<AppController, AppData>(
  AppController.new,
);

class AppController extends AsyncNotifier<AppData> {
  static const Duration _vaultSyncDebounceDuration = Duration(seconds: 2);
  static const int _targetSchemaVersion = AppPreferences.currentSchemaVersion;

  final Uuid _uuid = const Uuid();

  late final LocalStore _store;
  late final BackupService _backupService;
  late final ReminderService _reminderService;
  Timer? _vaultSyncDebounceTimer;
  AppData? _pendingVaultSyncData;
  AppData? _migrationRecoverySnapshot;

  @override
  Future<AppData> build() async {
    _store = ref.read(localStoreProvider);
    _backupService = ref.read(backupServiceProvider);
    _reminderService = ref.read(reminderServiceProvider);
    ref.onDispose(() {
      _vaultSyncDebounceTimer?.cancel();
    });

    final loaded = await _store.load();
    final data = await _migrateDataIfNeeded(loaded);
    unawaited(_syncReminderSchedule(data.preferences));
    return data;
  }

  AppData? get _currentData => state.valueOrNull;

  bool get hasMigrationFailure {
    final result = _currentData?.preferences.lastMigrationResult;
    return result?.startsWith('failed:') ?? false;
  }

  String? get migrationFailureReason {
    final result = _currentData?.preferences.lastMigrationResult;
    if (result == null || !result.startsWith('failed:')) {
      return null;
    }
    return result.substring('failed:'.length).trim();
  }

  Future<AppData> _migrateDataIfNeeded(AppData data) async {
    final prefs = data.preferences;
    final needsVersionUpgrade = prefs.dataSchemaVersion < _targetSchemaVersion;
    final hadPreviousFailure =
        prefs.lastMigrationResult?.startsWith('failed:') ?? false;

    if (!needsVersionUpgrade && !hadPreviousFailure) {
      return data;
    }

    try {
      final migrated = data.copyWith(
        preferences: prefs.copyWith(
          dataSchemaVersion: _targetSchemaVersion,
          lastMigrationResult: 'ok:${DateTime.now().toIso8601String()}',
        ),
      );
      await _store.overwrite(migrated);
      _migrationRecoverySnapshot = null;
      return migrated;
    } catch (error) {
      _migrationRecoverySnapshot = data;
      final failed = data.copyWith(
        preferences: prefs.copyWith(
          dataSchemaVersion: max(1, prefs.dataSchemaVersion).toInt(),
          lastMigrationResult: 'failed:${error.toString()}',
        ),
      );
      await _store.overwrite(failed);
      return failed;
    }
  }

  Future<void> retryDataMigration() async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    final candidate = (_migrationRecoverySnapshot ?? data).copyWith(
      preferences: (_migrationRecoverySnapshot ?? data).preferences.copyWith(
        clearLastMigrationResult: true,
      ),
    );
    final migrated = await _migrateDataIfNeeded(candidate);
    state = AsyncData(migrated);
    unawaited(_syncReminderSchedule(migrated.preferences));
  }

  Future<String> exportRawMigrationBackup({required String passphrase}) async {
    final snapshot = _migrationRecoverySnapshot ?? _currentData;
    if (snapshot == null) {
      throw StateError('No data available to export.');
    }
    return _backupService.exportToFile(snapshot, passphrase: passphrase);
  }

  Future<void> resetLocalData() async {
    final reset = AppData.empty();
    await _store.overwrite(reset);
    state = AsyncData(reset);
    _migrationRecoverySnapshot = null;
    unawaited(_syncReminderSchedule(reset.preferences));
  }

  Future<void> _persist(AppData data, {bool scheduleVaultSync = true}) async {
    state = AsyncData(data);
    await _store.save(data);
    if (scheduleVaultSync) {
      unawaited(this.scheduleVaultSync(data: data));
    }
  }

  Future<void> scheduleVaultSync({AppData? data}) async {
    final snapshot = data ?? _currentData;
    if (snapshot == null) {
      return;
    }

    final vaultPath = snapshot.preferences.backupVaultPath?.trim();
    if (vaultPath == null || vaultPath.isEmpty) {
      return;
    }

    _pendingVaultSyncData = snapshot;
    _vaultSyncDebounceTimer?.cancel();
    _vaultSyncDebounceTimer = Timer(_vaultSyncDebounceDuration, () {
      unawaited(_runDebouncedVaultSync());
    });
  }

  Future<void> _runDebouncedVaultSync() async {
    final snapshot = _pendingVaultSyncData;
    _pendingVaultSyncData = null;
    if (snapshot == null) {
      return;
    }

    final vaultPath = snapshot.preferences.backupVaultPath?.trim();
    if (vaultPath == null || vaultPath.isEmpty) {
      return;
    }

    try {
      final writtenPath = await _backupService.writeVaultSnapshot(
        data: snapshot,
        directoryPath: vaultPath,
      );
      if (writtenPath == null) {
        await _setVaultSyncStatus(
          error: 'Backup vault passphrase is not set.',
          clearLastSuccessAt: false,
        );
        return;
      }

      await _setVaultSyncStatus(
        successAt: DateTime.now(),
        clearLastError: true,
      );
    } catch (error) {
      await _setVaultSyncStatus(
        error: error.toString(),
        clearLastSuccessAt: false,
      );
    }
  }

  Future<void> _setVaultSyncStatus({
    DateTime? successAt,
    String? error,
    bool clearLastError = false,
    bool clearLastSuccessAt = false,
  }) async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    final updatedPreferences = data.preferences.copyWith(
      lastVaultSyncAt: successAt,
      lastVaultSyncError: error,
      clearLastVaultSyncError: clearLastError,
      clearLastVaultSyncAt: clearLastSuccessAt,
    );

    await _persist(
      data.copyWith(preferences: updatedPreferences),
      scheduleVaultSync: false,
    );
  }

  Future<void> _syncReminderSchedule(AppPreferences prefs) async {
    try {
      if (prefs.remindersEnabled) {
        await _reminderService.scheduleDailyReminder(
          hour: prefs.reminderHour,
          minute: prefs.reminderMinute,
          title: 'Glitch check-in',
          body: 'Pick one task and keep momentum.',
        );
        return;
      }

      await _reminderService.cancelReminder();
    } catch (_) {
      // Reminder scheduling should never block core persistence.
    }
  }

  List<TaskItem> todayTasks(DateTime date, {bool includeOverdue = true}) {
    final data = _currentData;
    if (data == null) {
      return const <TaskItem>[];
    }

    final day = normalizeDate(date);

    final items = data.tasks
        .where((task) {
          if (task.type == TaskType.habit) {
            if (!_isHabitDueOnDate(task, day)) {
              return false;
            }
            return !isHabitCompletedOnDate(task.id, day);
          }

          if (task.completed) {
            return false;
          }

          if (task.scheduledDate == null) {
            return includeOverdue;
          }

          if (isSameDay(task.scheduledDate!, day)) {
            return true;
          }

          return includeOverdue && task.scheduledDate!.isBefore(day);
        })
        .toList(growable: false);

    items.sort((a, b) {
      final dateComparison = (a.scheduledDate ?? a.createdAt).compareTo(
        b.scheduledDate ?? b.createdAt,
      );
      if (dateComparison != 0) {
        return dateComparison;
      }
      return a.createdAt.compareTo(b.createdAt);
    });

    return items;
  }

  List<TaskItem> allHabits() {
    final data = _currentData;
    if (data == null) {
      return const <TaskItem>[];
    }

    final habits = data.tasks
        .where((task) => task.type == TaskType.habit)
        .toList(growable: false);

    habits.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return habits;
  }

  List<TaskItem> allChores({bool includeCompleted = false}) {
    final data = _currentData;
    if (data == null) {
      return const <TaskItem>[];
    }

    final chores = data.tasks
        .where(
          (task) =>
              task.type == TaskType.chore &&
              (includeCompleted ? true : !task.completed),
        )
        .toList(growable: false);

    chores.sort((a, b) {
      final aDate = a.scheduledDate ?? a.createdAt;
      final bDate = b.scheduledDate ?? b.createdAt;
      final dateComparison = aDate.compareTo(bDate);
      if (dateComparison != 0) {
        return dateComparison;
      }
      return a.createdAt.compareTo(b.createdAt);
    });

    return chores;
  }

  List<TaskItem> completedTasks() {
    final data = _currentData;
    if (data == null) {
      return const <TaskItem>[];
    }

    final completed = data.tasks
        .where((task) => task.completed && task.type != TaskType.habit)
        .toList(growable: false);

    completed.sort((a, b) {
      final aDate = a.completedAt ?? a.createdAt;
      final bDate = b.completedAt ?? b.createdAt;
      return bDate.compareTo(aDate);
    });

    return completed;
  }

  List<ProjectItem> projects() {
    final data = _currentData;
    if (data == null) {
      return const <ProjectItem>[];
    }

    final projects = List<ProjectItem>.from(data.projects);
    projects.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return projects;
  }

  String? projectNameForId(String? projectId) {
    final normalizedId = projectId?.trim();
    if (normalizedId == null || normalizedId.isEmpty) {
      return null;
    }

    final data = _currentData;
    if (data == null) {
      return null;
    }

    for (final project in data.projects) {
      if (project.id == normalizedId) {
        final name = project.name.trim();
        return name.isEmpty ? null : name;
      }
    }

    return null;
  }

  List<TaskItem> milestonesForProject(String projectId) {
    final data = _currentData;
    if (data == null) {
      return const <TaskItem>[];
    }

    final milestones = data.tasks
        .where(
          (task) =>
              task.type == TaskType.milestone && task.projectId == projectId,
        )
        .toList(growable: false);

    milestones.sort((a, b) {
      final aDate = a.scheduledDate ?? a.createdAt;
      final bDate = b.scheduledDate ?? b.createdAt;
      return aDate.compareTo(bDate);
    });

    return milestones;
  }

  bool isHabitCompletedOnDate(String habitId, DateTime date) {
    final data = _currentData;
    if (data == null) {
      return false;
    }

    final day = normalizeDate(date);
    return data.habitLogs.any((log) {
      return log.habitId == habitId &&
          log.completed &&
          isSameDay(log.date, day);
    });
  }

  List<DateTime> completionDatesForHabit(String habitId) {
    final data = _currentData;
    if (data == null) {
      return const <DateTime>[];
    }

    final dates = data.habitLogs
        .where((log) => log.habitId == habitId && log.completed)
        .map((log) => normalizeDate(log.date))
        .toSet()
        .toList(growable: false);
    dates.sort();
    return dates;
  }

  int streakForHabit(String habitId) {
    final data = _currentData;
    if (data == null) {
      return 0;
    }

    final habit = _habitById(habitId, data);
    if (habit == null) {
      return 0;
    }

    final recurrence = habit.recurrence ?? HabitRecurrence.daily();
    if (recurrence.usesTimesPerWeek) {
      final target = recurrence.timesPerWeek ?? 1;
      final today = normalizeDate(DateTime.now());
      var weekCursor = _startOfWeek(today);
      var streak = 0;

      final thisWeekCount = _completedCountInWeek(
        data: data,
        habitId: habitId,
        weekStart: weekCursor,
      );
      if (thisWeekCount >= target) {
        streak += 1;
      }

      weekCursor = weekCursor.subtract(const Duration(days: 7));

      while (true) {
        final weeklyCount = _completedCountInWeek(
          data: data,
          habitId: habitId,
          weekStart: weekCursor,
        );
        if (weeklyCount < target) {
          break;
        }
        streak += 1;
        weekCursor = weekCursor.subtract(const Duration(days: 7));
      }

      return streak;
    }

    var cursor = normalizeDate(DateTime.now());
    var streak = 0;
    var safetyCounter = 0;

    while (safetyCounter < 3650) {
      if (_isHabitScheduledForDay(task: habit, day: cursor)) {
        final completed = isHabitCompletedOnDate(habitId, cursor);
        if (!completed) {
          break;
        }
        streak += 1;
      }

      cursor = cursor.subtract(const Duration(days: 1));
      safetyCounter += 1;
    }

    return streak;
  }

  int projectProgress(String projectId) {
    final milestones = milestonesForProject(projectId);
    if (milestones.isEmpty) {
      return 0;
    }

    final completeCount = milestones.where((m) => m.completed).length;
    return ((completeCount / milestones.length) * 100).round();
  }

  int activeMilestoneCount(String projectId) {
    return milestonesForProject(
      projectId,
    ).where((milestone) => !milestone.completed).length;
  }

  int habitCompletionsThisWeek(String habitId) {
    final data = _currentData;
    if (data == null) {
      return 0;
    }

    final weekStart = _startOfWeek(normalizeDate(DateTime.now()));
    return _completedCountInWeek(
      data: data,
      habitId: habitId,
      weekStart: weekStart,
    );
  }

  int habitWeeklyTarget(String habitId) {
    final data = _currentData;
    if (data == null) {
      return 0;
    }

    final habit = _habitById(habitId, data);
    if (habit == null) {
      return 0;
    }

    final recurrence = habit.recurrence ?? HabitRecurrence.daily();
    return recurrence.usesTimesPerWeek ? (recurrence.timesPerWeek ?? 1) : 0;
  }

  String habitStreakUnit(String habitId) {
    final data = _currentData;
    if (data == null) {
      return 'day';
    }
    final habit = _habitById(habitId, data);
    if (habit == null) {
      return 'day';
    }

    final recurrence = habit.recurrence ?? HabitRecurrence.daily();
    return recurrence.usesTimesPerWeek ? 'week' : 'day';
  }

  bool isHabitDueToday(TaskItem habit) {
    return _isHabitDueOnDate(habit, normalizeDate(DateTime.now()));
  }

  Future<void> addProject({required String name, String? description}) async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final project = ProjectItem(
      id: _uuid.v4(),
      name: trimmed,
      description: description?.trim().isEmpty == true
          ? null
          : description?.trim(),
      createdAt: DateTime.now(),
    );

    await _persist(
      data.copyWith(projects: <ProjectItem>[...data.projects, project]),
    );
  }

  Future<void> updateProject({
    required String projectId,
    required String name,
    String? description,
  }) async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final normalizedDescription = description?.trim();

    final updatedProjects = data.projects
        .map((project) {
          if (project.id != projectId) {
            return project;
          }

          return project.copyWith(
            name: trimmed,
            description: normalizedDescription,
            clearDescription:
                normalizedDescription == null || normalizedDescription.isEmpty,
          );
        })
        .toList(growable: false);

    await _persist(data.copyWith(projects: updatedProjects));
  }

  Future<void> deleteProject(String projectId) async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    final updatedProjects = data.projects
        .where((project) => project.id != projectId)
        .toList(growable: false);
    final updatedTasks = data.tasks
        .where(
          (task) =>
              !(task.type == TaskType.milestone && task.projectId == projectId),
        )
        .toList(growable: false);

    await _persist(
      data.copyWith(projects: updatedProjects, tasks: updatedTasks),
    );
  }

  Future<void> addTask({
    required String title,
    required TaskType type,
    String? description,
    DateTime? scheduledDate,
    HabitRecurrence? recurrence,
    int? estimatedMinutes,
    String? projectId,
    TaskPriority priority = TaskPriority.medium,
    TaskEffort effort = TaskEffort.light,
    TaskEnergyWindow energyWindow = TaskEnergyWindow.any,
  }) async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final normalizedDate = scheduledDate == null
        ? null
        : normalizeDate(scheduledDate);
    final normalizedDuration = estimatedMinutes != null && estimatedMinutes > 0
        ? estimatedMinutes
        : null;
    final normalizedProjectId = type == TaskType.milestone
        ? projectId?.trim()
        : null;
    if (type == TaskType.milestone &&
        (normalizedProjectId == null ||
            normalizedProjectId.isEmpty ||
            !data.projects.any(
              (project) => project.id == normalizedProjectId,
            ))) {
      return;
    }

    final task = TaskItem(
      id: _uuid.v4(),
      title: trimmed,
      description: description?.trim().isEmpty == true
          ? null
          : description?.trim(),
      type: type,
      scheduledDate: type == TaskType.habit ? normalizedDate : normalizedDate,
      completed: false,
      estimatedMinutes: normalizedDuration,
      projectId: normalizedProjectId,
      recurrence: type == TaskType.habit
          ? (recurrence ?? HabitRecurrence.daily())
          : null,
      createdAt: DateTime.now(),
      priority: priority,
      effort: effort,
      energyWindow: energyWindow,
    );

    await _persist(data.copyWith(tasks: <TaskItem>[...data.tasks, task]));
  }

  Future<void> updateTask({
    required String taskId,
    required String title,
    String? description,
    DateTime? scheduledDate,
    HabitRecurrence? recurrence,
    int? estimatedMinutes,
    String? projectId,
    TaskPriority? priority,
    TaskEffort? effort,
    TaskEnergyWindow? energyWindow,
  }) async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }

    TaskItem? existingTask;
    for (final task in data.tasks) {
      if (task.id == taskId) {
        existingTask = task;
        break;
      }
    }
    if (existingTask == null) {
      return;
    }

    final normalizedDescription = description?.trim();
    final normalizedDate = scheduledDate == null
        ? null
        : normalizeDate(scheduledDate);
    final normalizedDuration = estimatedMinutes != null && estimatedMinutes > 0
        ? estimatedMinutes
        : null;
    final normalizedRecurrence = existingTask.type == TaskType.habit
        ? (recurrence ?? HabitRecurrence.daily())
        : null;
    final normalizedProjectId = existingTask.type == TaskType.milestone
        ? projectId?.trim()
        : null;
    if (existingTask.type == TaskType.milestone &&
        (normalizedProjectId == null ||
            normalizedProjectId.isEmpty ||
            !data.projects.any(
              (project) => project.id == normalizedProjectId,
            ))) {
      return;
    }

    final updatedTasks = data.tasks
        .map((task) {
          if (task.id != taskId) {
            return task;
          }

          return task.copyWith(
            title: trimmed,
            description: normalizedDescription,
            clearDescription:
                normalizedDescription == null || normalizedDescription.isEmpty,
            scheduledDate: normalizedDate,
            clearScheduledDate: normalizedDate == null,
            estimatedMinutes: normalizedDuration,
            clearEstimatedMinutes: normalizedDuration == null,
            recurrence: normalizedRecurrence,
            clearRecurrence: normalizedRecurrence == null,
            projectId: normalizedProjectId,
            clearProjectId: normalizedProjectId == null,
            priority: priority,
            effort: effort,
            energyWindow: energyWindow,
          );
        })
        .toList(growable: false);

    await _persist(data.copyWith(tasks: updatedTasks));
  }

  Future<void> updateTaskDuration(String taskId, int minutes) async {
    final data = _currentData;
    if (data == null || minutes < 0) {
      return;
    }

    final updatedTasks = data.tasks
        .map((task) {
          if (task.id != taskId) {
            return task;
          }

          final existing = task.actualMinutes ?? 0;
          final merged = max(existing, minutes);
          return task.copyWith(actualMinutes: merged);
        })
        .toList(growable: false);

    await _persist(data.copyWith(tasks: updatedTasks));
  }

  Future<void> deleteTask(String taskId) async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    final updatedTasks = data.tasks
        .where((task) => task.id != taskId)
        .toList(growable: false);
    final updatedLogs = data.habitLogs
        .where((log) => log.habitId != taskId)
        .toList(growable: false);

    await _persist(data.copyWith(tasks: updatedTasks, habitLogs: updatedLogs));
  }

  Future<void> completeTask(String taskId, {int? actualMinutes}) async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    TaskItem? task;
    for (final item in data.tasks) {
      if (item.id == taskId) {
        task = item;
        break;
      }
    }
    if (task == null) {
      return;
    }

    if (task.type == TaskType.habit) {
      await completeHabitOnDate(taskId: taskId, date: DateTime.now());
      return;
    }

    final normalizedMinutes = (actualMinutes != null && actualMinutes > 0)
        ? actualMinutes
        : task.actualMinutes;

    final updatedTasks = data.tasks
        .map((item) {
          if (item.id != taskId) {
            return item;
          }

          return item.copyWith(
            completed: true,
            completedAt: DateTime.now(),
            actualMinutes: normalizedMinutes,
          );
        })
        .toList(growable: false);

    await _persist(data.copyWith(tasks: updatedTasks));
  }

  Future<void> reopenTask(String taskId) async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    final updatedTasks = data.tasks
        .map((task) {
          if (task.id != taskId) {
            return task;
          }

          return task.copyWith(completed: false, clearCompletedAt: true);
        })
        .toList(growable: false);

    await _persist(data.copyWith(tasks: updatedTasks));
  }

  Future<void> completeHabitOnDate({
    required String taskId,
    required DateTime date,
  }) async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    final day = normalizeDate(date);

    final existingIndex = data.habitLogs.indexWhere(
      (log) => log.habitId == taskId && isSameDay(log.date, day),
    );

    final updated = List<HabitLogItem>.from(data.habitLogs);
    if (existingIndex >= 0) {
      updated[existingIndex] = HabitLogItem(
        id: updated[existingIndex].id,
        habitId: taskId,
        date: day,
        completed: true,
      );
    } else {
      updated.add(
        HabitLogItem(
          id: _uuid.v4(),
          habitId: taskId,
          date: day,
          completed: true,
        ),
      );
    }

    await _persist(data.copyWith(habitLogs: updated));
  }

  Future<void> clearHabitOnDate({
    required String taskId,
    required DateTime date,
  }) async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    final day = normalizeDate(date);
    final updated = data.habitLogs
        .where((log) {
          if (log.habitId != taskId) {
            return true;
          }
          return !isSameDay(log.date, day);
        })
        .toList(growable: false);

    await _persist(data.copyWith(habitLogs: updated));
  }

  Future<void> undoHabitCompletion({
    required String taskId,
    required DateTime date,
  }) async {
    await clearHabitOnDate(taskId: taskId, date: date);
  }

  Future<void> toggleHabitToday(String taskId) async {
    final isDone = isHabitCompletedOnDate(taskId, DateTime.now());
    if (isDone) {
      await clearHabitOnDate(taskId: taskId, date: DateTime.now());
    } else {
      await completeHabitOnDate(taskId: taskId, date: DateTime.now());
    }
  }

  Future<void> updatePreferences(AppPreferences preferences) async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    await _persist(data.copyWith(preferences: preferences));
    unawaited(_syncReminderSchedule(preferences));
  }

  Future<void> setDarkMode(bool enabled) async {
    final prefs = _currentData?.preferences;
    if (prefs == null) {
      return;
    }

    await updatePreferences(prefs.copyWith(useDarkMode: enabled));
  }

  Future<void> setHighContrast(bool enabled) async {
    final prefs = _currentData?.preferences;
    if (prefs == null) {
      return;
    }

    await updatePreferences(prefs.copyWith(highContrast: enabled));
  }

  Future<void> setTextScale(double value) async {
    final prefs = _currentData?.preferences;
    if (prefs == null) {
      return;
    }

    final clamped = value.clamp(1.0, 1.35);
    await updatePreferences(prefs.copyWith(textScale: clamped.toDouble()));
  }

  Future<void> setDarkThemeStyle(DarkThemeStyle style) async {
    final prefs = _currentData?.preferences;
    if (prefs == null) {
      return;
    }
    await updatePreferences(prefs.copyWith(darkThemeStyle: style));
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    final prefs = _currentData?.preferences;
    if (prefs == null) {
      return;
    }

    await updatePreferences(prefs.copyWith(remindersEnabled: enabled));
  }

  Future<void> setReminderTime({required int hour, required int minute}) async {
    final prefs = _currentData?.preferences;
    if (prefs == null) {
      return;
    }

    final normalizedHour = hour.clamp(0, 23).toInt();
    final normalizedMinute = minute.clamp(0, 59).toInt();
    await updatePreferences(
      prefs.copyWith(
        reminderHour: normalizedHour,
        reminderMinute: normalizedMinute,
      ),
    );
  }

  Future<void> setVoiceTypingEnabled(bool enabled) async {
    final prefs = _currentData?.preferences;
    if (prefs == null) {
      return;
    }
    await updatePreferences(prefs.copyWith(voiceTypingEnabled: enabled));
  }

  Future<void> setVoiceTypingAllowNetworkFallback(bool enabled) async {
    final prefs = _currentData?.preferences;
    if (prefs == null) {
      return;
    }
    await updatePreferences(
      prefs.copyWith(voiceTypingAllowNetworkFallback: enabled),
    );
  }

  Future<bool> sendTestReminderNotification() async {
    try {
      return await _reminderService.showTestNotification(
        title: 'Glitch test reminder',
        body: 'Notifications are working. Pick one task and begin.',
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> configureBackupVault({
    required String directoryPath,
    required String passphrase,
  }) async {
    final data = _currentData;
    if (data == null) {
      throw StateError('App data is not available yet.');
    }

    final normalizedPath = directoryPath.trim();
    if (normalizedPath.isEmpty) {
      throw const FormatException('Backup vault path cannot be empty.');
    }

    final normalizedPassphrase = passphrase.trim();
    if (normalizedPassphrase.isEmpty) {
      throw const FormatException('Passphrase cannot be empty.');
    }

    await _backupService.exportToDirectory(
      data,
      directoryPath: normalizedPath,
      passphrase: normalizedPassphrase,
      fileName: BackupService.vaultSnapshotFileName,
    );
    await _backupService.storeVaultPassphrase(normalizedPassphrase);

    final updatedPreferences = data.preferences.copyWith(
      backupVaultPath: normalizedPath,
      backupVaultPromptDismissed: true,
      backupPromptDeferrals: 0,
      lastVaultSyncAt: DateTime.now(),
      clearLastVaultSyncError: true,
    );
    await _persist(
      data.copyWith(preferences: updatedPreferences),
      scheduleVaultSync: false,
    );
  }

  Future<void> incrementBackupPromptDeferrals() async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    final current = data.preferences.backupPromptDeferrals;
    final updatedPreferences = data.preferences.copyWith(
      backupPromptDeferrals: (current + 1).clamp(0, 365).toInt(),
    );
    await _persist(
      data.copyWith(preferences: updatedPreferences),
      scheduleVaultSync: false,
    );
  }

  Future<void> setBackupVaultPromptDismissed() async {
    final data = _currentData;
    if (data == null) {
      return;
    }
    if (data.preferences.backupVaultPromptDismissed) {
      return;
    }

    final updatedPreferences = data.preferences.copyWith(
      backupVaultPromptDismissed: true,
      backupPromptDeferrals: 0,
    );
    await _persist(
      data.copyWith(preferences: updatedPreferences),
      scheduleVaultSync: false,
    );
  }

  Future<void> clearBackupVaultConfiguration() async {
    final data = _currentData;
    if (data == null) {
      return;
    }

    await _backupService.clearVaultPassphrase();
    final updatedPreferences = data.preferences.copyWith(
      clearBackupVaultPath: true,
      backupVaultPromptDismissed: true,
      backupPromptDeferrals: 0,
      clearLastVaultSyncAt: true,
      clearLastVaultSyncError: true,
    );
    await _persist(data.copyWith(preferences: updatedPreferences));
  }

  Future<void> updateBackupVaultPassphrase({required String passphrase}) async {
    final data = _currentData;
    if (data == null) {
      throw StateError('App data is not available yet.');
    }

    final normalizedPassphrase = passphrase.trim();
    if (normalizedPassphrase.isEmpty) {
      throw const FormatException('Passphrase cannot be empty.');
    }

    final vaultPath = data.preferences.backupVaultPath?.trim();
    if (vaultPath == null || vaultPath.isEmpty) {
      throw StateError('Backup vault folder is not configured.');
    }

    await _backupService.exportToDirectory(
      data,
      directoryPath: vaultPath,
      passphrase: normalizedPassphrase,
      fileName: BackupService.vaultSnapshotFileName,
    );
    await _backupService.storeVaultPassphrase(normalizedPassphrase);
    await _setVaultSyncStatus(
      successAt: DateTime.now(),
      clearLastError: true,
      clearLastSuccessAt: false,
    );
  }

  Future<String> syncBackupVaultNow() async {
    final data = _currentData;
    if (data == null) {
      throw StateError('App data is not available yet.');
    }

    final vaultPath = data.preferences.backupVaultPath?.trim();
    if (vaultPath == null || vaultPath.isEmpty) {
      throw StateError('Backup vault folder is not configured.');
    }

    try {
      final writtenPath = await _backupService.writeVaultSnapshot(
        data: data,
        directoryPath: vaultPath,
      );
      if (writtenPath == null) {
        await _setVaultSyncStatus(
          error: 'Backup vault passphrase is not set.',
          clearLastSuccessAt: false,
        );
        throw StateError('Backup vault passphrase is not set.');
      }

      await _setVaultSyncStatus(
        successAt: DateTime.now(),
        clearLastError: true,
      );
      return writtenPath;
    } catch (error) {
      await _setVaultSyncStatus(
        error: error.toString(),
        clearLastSuccessAt: false,
      );
      rethrow;
    }
  }

  Future<String> exportBackup({required String passphrase}) async {
    final data = _currentData;
    if (data == null) {
      throw StateError('App data is not available yet.');
    }

    return _backupService.exportToFile(data, passphrase: passphrase);
  }

  Future<void> importBackupFromPath(
    String path, {
    required String passphrase,
  }) async {
    final imported = await _backupService.importFromFile(
      path,
      passphrase: passphrase,
    );
    state = AsyncData(imported);
    await _store.overwrite(imported);
    unawaited(_syncReminderSchedule(imported.preferences));
  }

  DayProgress dayProgress(DateTime date) {
    final data = _currentData;
    if (data == null) {
      return const DayProgress(plannedCount: 0, completedCount: 0);
    }

    final day = normalizeDate(date);
    var plannedCount = 0;
    var completedCount = 0;

    for (final task in data.tasks) {
      if (task.type == TaskType.habit) {
        if (_isHabitPlannedForDay(task: task, day: day, data: data)) {
          plannedCount += 1;
          if (isHabitCompletedOnDate(task.id, day)) {
            completedCount += 1;
          }
        }
        continue;
      }

      if (task.scheduledDate == null) {
        continue;
      }

      if (!isSameDay(task.scheduledDate!, day)) {
        continue;
      }

      plannedCount += 1;
      if (task.completed &&
          task.completedAt != null &&
          isSameDay(task.completedAt!, day)) {
        completedCount += 1;
      }
    }

    return DayProgress(
      plannedCount: plannedCount,
      completedCount: completedCount,
    );
  }

  Map<DateTime, DayProgress> dayProgressRange({
    required DateTime start,
    required DateTime end,
  }) {
    final from = normalizeDate(start);
    final to = normalizeDate(end);

    if (to.isBefore(from)) {
      return const <DateTime, DayProgress>{};
    }

    final map = <DateTime, DayProgress>{};
    var cursor = from;
    while (!cursor.isAfter(to)) {
      map[cursor] = dayProgress(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    return map;
  }

  List<HabitLogItem> completedHabitLogs() {
    final data = _currentData;
    if (data == null) {
      return const <HabitLogItem>[];
    }

    final logs = data.habitLogs
        .where((log) => log.completed)
        .toList(growable: false);
    logs.sort((a, b) => b.date.compareTo(a.date));
    return logs;
  }

  TaskItem? _habitById(String habitId, AppData data) {
    for (final task in data.tasks) {
      if (task.id == habitId && task.type == TaskType.habit) {
        return task;
      }
    }
    return null;
  }

  DateTime _startOfWeek(DateTime day) {
    return normalizeDate(
      day.subtract(Duration(days: day.weekday - DateTime.monday)),
    );
  }

  int _completedCountInWeek({
    required AppData data,
    required String habitId,
    required DateTime weekStart,
  }) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    return data.habitLogs
        .where((log) {
          if (log.habitId != habitId || !log.completed) {
            return false;
          }
          final date = normalizeDate(log.date);
          return !date.isBefore(weekStart) && !date.isAfter(weekEnd);
        })
        .map((log) => normalizeDate(log.date))
        .toSet()
        .length;
  }

  int _completedCountInWeekBeforeDay({
    required AppData data,
    required String habitId,
    required DateTime weekStart,
    required DateTime day,
  }) {
    return data.habitLogs
        .where((log) {
          if (log.habitId != habitId || !log.completed) {
            return false;
          }
          final date = normalizeDate(log.date);
          return !date.isBefore(weekStart) && date.isBefore(day);
        })
        .map((log) => normalizeDate(log.date))
        .toSet()
        .length;
  }

  bool _isHabitPlannedForDay({
    required TaskItem task,
    required DateTime day,
    required AppData data,
  }) {
    final recurrence = task.recurrence ?? HabitRecurrence.daily();
    switch (recurrence.type) {
      case HabitRecurrenceType.daily:
        return true;
      case HabitRecurrenceType.specificDays:
        return recurrence.daysOfWeek.contains(day.weekday);
      case HabitRecurrenceType.timesPerWeek:
        final target = recurrence.timesPerWeek ?? 1;
        final weekStart = _startOfWeek(day);
        final completedBeforeDay = _completedCountInWeekBeforeDay(
          data: data,
          habitId: task.id,
          weekStart: weekStart,
          day: day,
        );
        return completedBeforeDay < target;
    }
  }

  bool _isHabitScheduledForDay({
    required TaskItem task,
    required DateTime day,
  }) {
    final recurrence = task.recurrence ?? HabitRecurrence.daily();

    switch (recurrence.type) {
      case HabitRecurrenceType.daily:
        return true;
      case HabitRecurrenceType.specificDays:
        return recurrence.daysOfWeek.contains(day.weekday);
      case HabitRecurrenceType.timesPerWeek:
        final data = _currentData;
        if (data == null) {
          return true;
        }
        return _isHabitPlannedForDay(task: task, day: day, data: data);
    }
  }

  bool _isHabitDueOnDate(TaskItem task, DateTime day) {
    final recurrence = task.recurrence ?? HabitRecurrence.daily();

    switch (recurrence.type) {
      case HabitRecurrenceType.daily:
        return true;
      case HabitRecurrenceType.specificDays:
        return recurrence.daysOfWeek.contains(day.weekday);
      case HabitRecurrenceType.timesPerWeek:
        final data = _currentData;
        if (data == null) {
          return true;
        }
        final target = recurrence.timesPerWeek ?? 1;
        final weekStart = _startOfWeek(day);
        final completedBeforeDay = _completedCountInWeekBeforeDay(
          data: data,
          habitId: task.id,
          weekStart: weekStart,
          day: day,
        );
        return completedBeforeDay < target;
    }
  }
}

class CompletedItem {
  const CompletedItem({
    required this.label,
    required this.type,
    required this.date,
  });

  final String label;
  final String type;
  final DateTime date;
}

class DayProgress {
  const DayProgress({required this.plannedCount, required this.completedCount});

  final int plannedCount;
  final int completedCount;

  bool get hadAnythingPlanned => plannedCount > 0;

  bool get isPerfectDay => hadAnythingPlanned && completedCount >= plannedCount;

  double get ratio {
    if (plannedCount <= 0) {
      return 0;
    }
    return (completedCount / plannedCount).clamp(0, 1);
  }
}
