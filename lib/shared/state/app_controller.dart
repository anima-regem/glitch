import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/app_data.dart';
import '../../core/models/app_preferences.dart';
import '../../core/models/habit_log.dart';
import '../../core/models/project.dart';
import '../../core/models/task.dart';
import '../../core/services/backup_service.dart';
import '../../core/storage/local_store.dart';
import '../../core/utils/date_time_utils.dart';

final localStoreProvider = Provider<LocalStore>((ref) => HiveLocalStore());

final backupServiceProvider = Provider<BackupService>((ref) => BackupService());

final appControllerProvider = AsyncNotifierProvider<AppController, AppData>(
  AppController.new,
);

class AppController extends AsyncNotifier<AppData> {
  final Uuid _uuid = const Uuid();

  late final LocalStore _store;
  late final BackupService _backupService;

  @override
  Future<AppData> build() async {
    _store = ref.read(localStoreProvider);
    _backupService = ref.read(backupServiceProvider);
    return _store.load();
  }

  AppData? get _currentData => state.valueOrNull;

  Future<void> _persist(AppData data) async {
    state = AsyncData(data);
    await _store.save(data);
  }

  List<TaskItem> todayTasks(DateTime date) {
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
            return true;
          }

          return isSameDay(task.scheduledDate!, day);
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
      projectId: type == TaskType.milestone ? projectId : null,
      recurrence: type == TaskType.habit
          ? (recurrence ?? HabitRecurrence.daily())
          : null,
      createdAt: DateTime.now(),
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
        ? projectId
        : null;

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

  Future<String> exportBackup() async {
    final data = _currentData;
    if (data == null) {
      throw StateError('App data is not available yet.');
    }

    return _backupService.exportToFile(data);
  }

  Future<void> importBackupFromPath(String path) async {
    final imported = await _backupService.importFromFile(path);
    state = AsyncData(imported);
    await _store.overwrite(imported);
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
        if (_isHabitScheduledForDay(task: task, day: day)) {
          plannedCount += 1;
          if (isHabitCompletedOnDate(task.id, day)) {
            completedCount += 1;
          }
        }
        continue;
      }

      if (_isTaskRelevantForDay(task: task, day: day)) {
        plannedCount += 1;
        if (task.completed &&
            task.completedAt != null &&
            isSameDay(task.completedAt!, day)) {
          completedCount += 1;
        }
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
        return _isHabitDueOnDate(task, day);
    }
  }

  bool _isTaskRelevantForDay({required TaskItem task, required DateTime day}) {
    if (task.scheduledDate != null) {
      return isSameDay(task.scheduledDate!, day);
    }

    if (!task.completed) {
      return true;
    }

    if (task.completedAt != null) {
      return isSameDay(task.completedAt!, day);
    }

    return false;
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
        final completedCount = _completedCountInWeek(
          data: data,
          habitId: task.id,
          weekStart: weekStart,
        );
        return completedCount < target;
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
