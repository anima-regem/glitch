import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/core/models/app_data.dart';
import 'package:glitch/core/models/app_preferences.dart';
import 'package:glitch/core/models/habit_log.dart';
import 'package:glitch/core/models/project.dart';
import 'package:glitch/core/models/task.dart';
import 'package:glitch/core/services/backup_service.dart';

void main() {
  test('passphrase backup round-trips across service instances', () async {
    final source = _sampleData();
    final exported = BackupService().exportToJson(
      source,
      passphrase: 'correct horse battery staple',
    );

    final envelope = Map<String, dynamic>.from(
      jsonDecode(exported) as Map<dynamic, dynamic>,
    );
    expect(envelope['version'], 2);
    expect(envelope['kdf'], 'PBKDF2-HMAC-SHA256');
    expect((envelope['salt'] as String).isNotEmpty, isTrue);

    final restored = await BackupService().importFromJson(
      exported,
      passphrase: 'correct horse battery staple',
    );

    expect(restored.toJson(), equals(source.toJson()));
  });

  test('import fails with an incorrect passphrase', () async {
    final exported = BackupService().exportToJson(
      _sampleData(),
      passphrase: 'top-secret-passphrase',
    );

    await expectLater(
      BackupService().importFromJson(exported, passphrase: 'wrong-passphrase'),
      throwsA(anything),
    );
  });
}

AppData _sampleData() {
  final createdAt = DateTime.utc(2026, 2, 19, 10);

  return AppData(
    tasks: <TaskItem>[
      TaskItem(
        id: 'chore-1',
        title: 'Pay bills',
        type: TaskType.chore,
        completed: true,
        createdAt: createdAt,
        scheduledDate: DateTime.utc(2026, 2, 19),
        completedAt: DateTime.utc(2026, 2, 19, 11),
        estimatedMinutes: 10,
        actualMinutes: 12,
      ),
      TaskItem(
        id: 'habit-1',
        title: 'Read 20 pages',
        type: TaskType.habit,
        completed: false,
        createdAt: createdAt,
        recurrence: HabitRecurrence.timesPerWeek(4),
      ),
    ],
    habitLogs: <HabitLogItem>[
      HabitLogItem(
        id: 'habit-log-1',
        habitId: 'habit-1',
        date: DateTime.utc(2026, 2, 18),
        completed: true,
      ),
    ],
    projects: <ProjectItem>[
      ProjectItem(
        id: 'project-1',
        name: 'Launch',
        description: 'Q1 launch tasks',
        createdAt: createdAt,
      ),
    ],
    preferences: const AppPreferences(
      useDarkMode: true,
      highContrast: false,
      textScale: 1.0,
      darkThemeStyle: DarkThemeStyle.black,
      remindersEnabled: false,
      reminderHour: 20,
      reminderMinute: 0,
      backupPromptDeferrals: 0,
      voiceTypingEnabled: true,
      voiceTypingAllowNetworkFallback: false,
    ),
  );
}
