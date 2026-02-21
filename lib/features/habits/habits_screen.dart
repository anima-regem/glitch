import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/task.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
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
                onTap: () async {
                  await _showHabitInsights(context, habit.id);
                },
                title: Text(
                  habit.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${habit.recurrence?.label ?? 'Daily'} • $streak $streakUnit streak$weeklySuffix${_descriptionSuffix(habit.description)}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
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

  Future<void> _showHabitInsights(BuildContext context, String habitId) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: _HabitInsightsSheet(habitId: habitId),
        );
      },
    );
  }
}

String _descriptionSuffix(String? description) {
  final text = description?.trim();
  if (text == null || text.isEmpty) {
    return '';
  }
  return '\n$text';
}

enum _HabitAction { edit, delete }

class _HabitInsightsSheet extends ConsumerWidget {
  const _HabitInsightsSheet({required this.habitId});

  final String habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.glitchPalette;
    final state = ref.watch(appControllerProvider);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('Unable to load habit details')),
      data: (_) {
        final notifier = ref.read(appControllerProvider.notifier);
        final habits = notifier.allHabits();
        TaskItem? habit;
        for (final item in habits) {
          if (item.id == habitId) {
            habit = item;
            break;
          }
        }
        if (habit == null) {
          return const Center(child: Text('Habit not found'));
        }

        final streak = notifier.streakForHabit(habit.id);
        final streakUnit = notifier.habitStreakUnit(habit.id);
        final weeklyTarget = notifier.habitWeeklyTarget(habit.id);
        final weeklyCompletions = notifier.habitCompletionsThisWeek(habit.id);
        final completionDates = notifier.completionDatesForHabit(habit.id);
        final completionSet = completionDates.map(normalizeDate).toSet();
        final end = normalizeDate(DateTime.now());
        final start = end.subtract(const Duration(days: 139));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: <Widget>[
            Text(
              habit.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              habit.recurrence?.label ?? 'Daily',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _InsightCard(
                    title: 'Streak',
                    value: '$streak $streakUnit${streak == 1 ? '' : 's'}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InsightCard(
                    title: weeklyTarget > 0 ? 'This Week' : 'Completions',
                    value: weeklyTarget > 0
                        ? '$weeklyCompletions / $weeklyTarget'
                        : '$weeklyCompletions',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _HabitHeatmap(start: start, end: end, completedDays: completionSet),
          ],
        );
      },
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitHeatmap extends StatelessWidget {
  const _HabitHeatmap({
    required this.start,
    required this.end,
    required this.completedDays,
  });

  final DateTime start;
  final DateTime end;
  final Set<DateTime> completedDays;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    final firstDay = normalizeDate(start);
    final lastDay = normalizeDate(end);
    final firstColumnDay = firstDay.subtract(
      Duration(days: firstDay.weekday - DateTime.monday),
    );
    final totalDays = lastDay.difference(firstColumnDay).inDays + 1;
    final totalWeeks = (totalDays / 7).ceil();

    final weeks = List<List<DateTime>>.generate(totalWeeks, (columnIndex) {
      final weekStart = firstColumnDay.add(Duration(days: columnIndex * 7));
      return List<DateTime>.generate(
        7,
        (rowIndex) => weekStart.add(Duration(days: rowIndex)),
        growable: false,
      );
    }, growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Habit Heatmap',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Last 20 weeks of completions.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: weeks
                    .map((week) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Column(
                          children: week
                              .map((day) {
                                final normalized = normalizeDate(day);
                                final inRange =
                                    !normalized.isBefore(firstDay) &&
                                    !normalized.isAfter(lastDay);
                                final done = completedDays.contains(normalized);

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Tooltip(
                                    message:
                                        '${formatGroupDate(normalized)} • ${done ? 'Completed' : 'Not completed'}',
                                    child: Container(
                                      width: 13,
                                      height: 13,
                                      decoration: BoxDecoration(
                                        color: !inRange
                                            ? Colors.transparent
                                            : done
                                            ? palette.accent
                                            : palette.surfaceRaised,
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(
                                          color: palette.surfaceStroke,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Legend: neutral = not completed, accent = completed',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
