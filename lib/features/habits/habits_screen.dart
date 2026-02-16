import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/task.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/state/app_controller.dart';
import '../tasks/task_creation_sheet.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('Failed to load habits')),
      data: (_) {
        final palette = context.glitchPalette;
        final notifier = ref.read(appControllerProvider.notifier);
        final habits = notifier.allHabits();

        if (habits.isEmpty) {
          return Center(
            child: Text(
              'No habits yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemBuilder: (context, index) {
            final habit = habits[index];
            final completedToday = notifier.isHabitCompletedOnDate(
              habit.id,
              DateTime.now(),
            );
            final streak = notifier.streakForHabit(habit.id);
            final streakUnit = notifier.habitStreakUnit(habit.id);
            final weeklyTarget = notifier.habitWeeklyTarget(habit.id);
            final weeklyCompletions = notifier.habitCompletionsThisWeek(
              habit.id,
            );
            final weeklySuffix = weeklyTarget > 0
                ? ' • $weeklyCompletions/$weeklyTarget this week'
                : '';

            return Card(
              child: ListTile(
                title: Text(
                  habit.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${habit.recurrence?.label ?? 'Daily'} • $streak $streakUnit streak$weeklySuffix',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      icon: Icon(
                        completedToday
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                      ),
                      color: completedToday
                          ? palette.accent
                          : palette.textMuted,
                      onPressed: () {
                        ref
                            .read(appControllerProvider.notifier)
                            .toggleHabitToday(habit.id);
                      },
                    ),
                    PopupMenuButton<_HabitAction>(
                      tooltip: 'Habit actions',
                      onSelected: (action) async {
                        switch (action) {
                          case _HabitAction.edit:
                            await TaskCreationSheet.open(
                              context,
                              existingTask: habit,
                            );
                            break;
                          case _HabitAction.delete:
                            await _confirmDeleteHabit(context, ref, habit);
                            break;
                        }
                      },
                      itemBuilder: (context) =>
                          const <PopupMenuEntry<_HabitAction>>[
                            PopupMenuItem<_HabitAction>(
                              value: _HabitAction.edit,
                              child: Text('Edit'),
                            ),
                            PopupMenuItem<_HabitAction>(
                              value: _HabitAction.delete,
                              child: Text('Delete'),
                            ),
                          ],
                    ),
                  ],
                ),
              ),
            );
          },
          separatorBuilder: (_, index) => const SizedBox(height: 8),
          itemCount: habits.length,
        );
      },
    );
  }

  Future<void> _confirmDeleteHabit(
    BuildContext context,
    WidgetRef ref,
    TaskItem habit,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete habit?'),
          content: Text('Delete "${habit.title}" and its history logs?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await ref.read(appControllerProvider.notifier).deleteTask(habit.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Habit deleted')));
  }
}

enum _HabitAction { edit, delete }
