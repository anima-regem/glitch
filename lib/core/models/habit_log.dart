import 'package:flutter/foundation.dart';

@immutable
class HabitLogItem {
  const HabitLogItem({
    required this.id,
    required this.habitId,
    required this.date,
    required this.completed,
  });

  final String id;
  final String habitId;
  final DateTime date;
  final bool completed;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'habitId': habitId,
      'date': date.toIso8601String(),
      'completed': completed,
    };
  }

  factory HabitLogItem.fromJson(Map<String, dynamic> json) {
    return HabitLogItem(
      id: json['id'] as String,
      habitId: json['habitId'] as String,
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      completed: json['completed'] as bool? ?? true,
    );
  }
}
