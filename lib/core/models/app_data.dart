import 'package:flutter/foundation.dart';

import 'app_preferences.dart';
import 'habit_log.dart';
import 'project.dart';
import 'task.dart';

@immutable
class AppData {
  const AppData({
    required this.tasks,
    required this.habitLogs,
    required this.projects,
    required this.preferences,
  });

  factory AppData.empty() {
    return AppData(
      tasks: const <TaskItem>[],
      habitLogs: const <HabitLogItem>[],
      projects: const <ProjectItem>[],
      preferences: AppPreferences.defaults(),
    );
  }

  final List<TaskItem> tasks;
  final List<HabitLogItem> habitLogs;
  final List<ProjectItem> projects;
  final AppPreferences preferences;

  AppData copyWith({
    List<TaskItem>? tasks,
    List<HabitLogItem>? habitLogs,
    List<ProjectItem>? projects,
    AppPreferences? preferences,
  }) {
    return AppData(
      tasks: tasks ?? this.tasks,
      habitLogs: habitLogs ?? this.habitLogs,
      projects: projects ?? this.projects,
      preferences: preferences ?? this.preferences,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tasks': tasks.map((task) => task.toJson()).toList(growable: false),
      'habitLogs': habitLogs.map((log) => log.toJson()).toList(growable: false),
      'projects': projects
          .map((project) => project.toJson())
          .toList(growable: false),
      'preferences': preferences.toJson(),
    };
  }

  factory AppData.fromJson(Map<String, dynamic> json) {
    return AppData(
      tasks: (json['tasks'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map((task) => TaskItem.fromJson(Map<String, dynamic>.from(task)))
          .toList(growable: false),
      habitLogs: (json['habitLogs'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map((log) => HabitLogItem.fromJson(Map<String, dynamic>.from(log)))
          .toList(growable: false),
      projects: (json['projects'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (project) =>
                ProjectItem.fromJson(Map<String, dynamic>.from(project)),
          )
          .toList(growable: false),
      preferences: AppPreferences.fromJson(
        Map<String, dynamic>.from(
          json['preferences'] as Map<dynamic, dynamic>? ??
              const <String, dynamic>{},
        ),
      ),
    );
  }
}
