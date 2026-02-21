import 'package:flutter/foundation.dart';

enum TaskType { chore, habit, milestone }

enum HabitRecurrenceType { daily, specificDays, timesPerWeek }

enum TaskPriority { low, medium, high }

enum TaskEffort { light, deep }

enum TaskEnergyWindow { any, morning, afternoon, evening }

extension TaskTypeLabel on TaskType {
  String get label {
    switch (this) {
      case TaskType.chore:
        return 'Chore';
      case TaskType.habit:
        return 'Habit';
      case TaskType.milestone:
        return 'Milestone';
    }
  }

  static TaskType fromStorage(String value) {
    return TaskType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => TaskType.chore,
    );
  }
}

extension HabitRecurrenceTypeLabel on HabitRecurrenceType {
  String get label {
    switch (this) {
      case HabitRecurrenceType.daily:
        return 'Daily';
      case HabitRecurrenceType.specificDays:
        return 'Specific days';
      case HabitRecurrenceType.timesPerWeek:
        return 'X days/week';
    }
  }

  static HabitRecurrenceType fromStorage(String value) {
    return HabitRecurrenceType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => HabitRecurrenceType.daily,
    );
  }
}

extension TaskPriorityLabel on TaskPriority {
  String get label {
    switch (this) {
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.high:
        return 'High';
    }
  }

  static TaskPriority fromStorage(String? value) {
    return TaskPriority.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TaskPriority.medium,
    );
  }
}

extension TaskEffortLabel on TaskEffort {
  String get label {
    switch (this) {
      case TaskEffort.light:
        return 'Light';
      case TaskEffort.deep:
        return 'Deep';
    }
  }

  static TaskEffort fromStorage(String? value) {
    return TaskEffort.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TaskEffort.light,
    );
  }
}

extension TaskEnergyWindowLabel on TaskEnergyWindow {
  String get label {
    switch (this) {
      case TaskEnergyWindow.any:
        return 'Any time';
      case TaskEnergyWindow.morning:
        return 'Morning';
      case TaskEnergyWindow.afternoon:
        return 'Afternoon';
      case TaskEnergyWindow.evening:
        return 'Evening';
    }
  }

  static TaskEnergyWindow fromStorage(String? value) {
    return TaskEnergyWindow.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TaskEnergyWindow.any,
    );
  }
}

@immutable
class HabitRecurrence {
  const HabitRecurrence._({
    required this.type,
    this.daysOfWeek = const <int>[],
    this.timesPerWeek,
  });

  factory HabitRecurrence.daily() {
    return HabitRecurrence._(type: HabitRecurrenceType.daily);
  }

  factory HabitRecurrence.specificDays(Iterable<int> days) {
    final normalized =
        days
            .where(
              (value) => value >= DateTime.monday && value <= DateTime.sunday,
            )
            .toSet()
            .toList(growable: false)
          ..sort();
    final safeDays = normalized.isEmpty
        ? const <int>[DateTime.monday]
        : normalized;

    return HabitRecurrence._(
      type: HabitRecurrenceType.specificDays,
      daysOfWeek: safeDays,
    );
  }

  factory HabitRecurrence.timesPerWeek(int timesPerWeek) {
    final clamped = timesPerWeek.clamp(1, 7).toInt();
    return HabitRecurrence._(
      type: HabitRecurrenceType.timesPerWeek,
      timesPerWeek: clamped,
    );
  }

  final HabitRecurrenceType type;
  final List<int> daysOfWeek;
  final int? timesPerWeek;

  String get label {
    switch (type) {
      case HabitRecurrenceType.daily:
        return 'Daily';
      case HabitRecurrenceType.specificDays:
        if (daysOfWeek.isEmpty) {
          return 'Specific days';
        }
        return daysOfWeek.map(HabitRecurrence.shortWeekdayLabel).join(', ');
      case HabitRecurrenceType.timesPerWeek:
        final target = timesPerWeek ?? 1;
        return '$target days/week';
    }
  }

  bool get usesSpecificDays => type == HabitRecurrenceType.specificDays;

  bool get usesTimesPerWeek => type == HabitRecurrenceType.timesPerWeek;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.name,
      'daysOfWeek': daysOfWeek,
      'timesPerWeek': timesPerWeek,
    };
  }

  factory HabitRecurrence.fromJson(dynamic raw, {int? legacyWeeklyWeekday}) {
    if (raw is String) {
      if (raw == 'daily') {
        return HabitRecurrence.daily();
      }
      if (raw == 'weekly') {
        final weekday = legacyWeeklyWeekday ?? DateTime.monday;
        return HabitRecurrence.specificDays(<int>[weekday]);
      }
      return HabitRecurrence.daily();
    }

    if (raw is Map<dynamic, dynamic>) {
      final map = Map<String, dynamic>.from(raw);
      final type = HabitRecurrenceTypeLabel.fromStorage(
        map['type'] as String? ?? 'daily',
      );

      switch (type) {
        case HabitRecurrenceType.daily:
          return HabitRecurrence.daily();
        case HabitRecurrenceType.specificDays:
          final days = (map['daysOfWeek'] as List<dynamic>? ?? const [])
              .map((value) {
                if (value is num) {
                  return value.toInt();
                }
                return int.tryParse(value.toString()) ?? -1;
              })
              .toList(growable: false);
          return HabitRecurrence.specificDays(days);
        case HabitRecurrenceType.timesPerWeek:
          final target = (map['timesPerWeek'] as num?)?.toInt() ?? 1;
          return HabitRecurrence.timesPerWeek(target);
      }
    }

    return HabitRecurrence.daily();
  }

  static String shortWeekdayLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
      default:
        return '?';
    }
  }
}

@immutable
class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.type,
    required this.completed,
    required this.createdAt,
    this.description,
    this.scheduledDate,
    this.estimatedMinutes,
    this.actualMinutes,
    this.projectId,
    this.recurrence,
    this.completedAt,
    this.priority = TaskPriority.medium,
    this.effort = TaskEffort.light,
    this.energyWindow = TaskEnergyWindow.any,
  });

  final String id;
  final String title;
  final String? description;
  final TaskType type;
  final DateTime? scheduledDate;
  final bool completed;
  final int? estimatedMinutes;
  final int? actualMinutes;
  final String? projectId;
  final HabitRecurrence? recurrence;
  final DateTime createdAt;
  final DateTime? completedAt;
  final TaskPriority priority;
  final TaskEffort effort;
  final TaskEnergyWindow energyWindow;

  bool get isHabit => type == TaskType.habit;

  TaskItem copyWith({
    String? id,
    String? title,
    String? description,
    TaskType? type,
    DateTime? scheduledDate,
    bool? completed,
    int? estimatedMinutes,
    int? actualMinutes,
    String? projectId,
    HabitRecurrence? recurrence,
    DateTime? createdAt,
    DateTime? completedAt,
    TaskPriority? priority,
    TaskEffort? effort,
    TaskEnergyWindow? energyWindow,
    bool clearDescription = false,
    bool clearScheduledDate = false,
    bool clearEstimatedMinutes = false,
    bool clearActualMinutes = false,
    bool clearProjectId = false,
    bool clearRecurrence = false,
    bool clearCompletedAt = false,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: clearDescription ? null : (description ?? this.description),
      type: type ?? this.type,
      scheduledDate: clearScheduledDate
          ? null
          : (scheduledDate ?? this.scheduledDate),
      completed: completed ?? this.completed,
      estimatedMinutes: clearEstimatedMinutes
          ? null
          : (estimatedMinutes ?? this.estimatedMinutes),
      actualMinutes: clearActualMinutes
          ? null
          : (actualMinutes ?? this.actualMinutes),
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      recurrence: clearRecurrence ? null : (recurrence ?? this.recurrence),
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      priority: priority ?? this.priority,
      effort: effort ?? this.effort,
      energyWindow: energyWindow ?? this.energyWindow,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'description': description,
      'type': type.name,
      'scheduledDate': scheduledDate?.toIso8601String(),
      'completed': completed,
      'estimatedMinutes': estimatedMinutes,
      'actualMinutes': actualMinutes,
      'projectId': projectId,
      'recurrence': recurrence?.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'priority': priority.name,
      'effort': effort.name,
      'energyWindow': energyWindow.name,
    };
  }

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    final scheduledDate = _parseDateTime(json['scheduledDate']);
    final createdAt = _parseDateTime(json['createdAt']) ?? DateTime.now();

    return TaskItem(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      type: TaskTypeLabel.fromStorage(json['type'] as String? ?? 'chore'),
      scheduledDate: scheduledDate,
      completed: json['completed'] as bool? ?? false,
      estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt(),
      actualMinutes: (json['actualMinutes'] as num?)?.toInt(),
      projectId: json['projectId'] as String?,
      recurrence: json['recurrence'] == null
          ? null
          : HabitRecurrence.fromJson(
              json['recurrence'],
              legacyWeeklyWeekday: (scheduledDate ?? createdAt).weekday,
            ),
      createdAt: createdAt,
      completedAt: _parseDateTime(json['completedAt']),
      priority: TaskPriorityLabel.fromStorage(json['priority'] as String?),
      effort: TaskEffortLabel.fromStorage(json['effort'] as String?),
      energyWindow: TaskEnergyWindowLabel.fromStorage(
        json['energyWindow'] as String?,
      ),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}
