import 'package:flutter/foundation.dart';

@immutable
class ProjectItem {
  const ProjectItem({
    required this.id,
    required this.name,
    required this.createdAt,
    this.description,
  });

  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;

  ProjectItem copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    bool clearDescription = false,
  }) {
    return ProjectItem(
      id: id ?? this.id,
      name: name ?? this.name,
      description: clearDescription ? null : (description ?? this.description),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ProjectItem.fromJson(Map<String, dynamic> json) {
    return ProjectItem(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
