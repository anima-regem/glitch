import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/task.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../shared/state/app_controller.dart';

class CompletedScreen extends ConsumerWidget {
  const CompletedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => const Center(child: Text('Failed to load')),
      data: (data) {
        final notifier = ref.read(appControllerProvider.notifier);
        final completedTasks = notifier.completedTasks();
        final completedHabitLogs = notifier.completedHabitLogs();
        final taskMap = {for (final task in data.tasks) task.id: task};
        final projectMap = {
          for (final project in data.projects) project.id: project.name,
        };

        final allEntries = <_CompletedEntry>[
          ...completedTasks.map(
            (task) => _CompletedEntry(
              kind: _CompletedEntryKind.task,
              label: task.title,
              typeLabel: _completedTypeLabel(task, projectMap),
              date: normalizeDate(task.completedAt ?? task.createdAt),
              taskId: task.id,
            ),
          ),
          ...completedHabitLogs.map(
            (log) => _CompletedEntry(
              kind: _CompletedEntryKind.habitLog,
              label: taskMap[log.habitId]?.title ?? 'Habit',
              typeLabel: 'Habit',
              date: normalizeDate(log.date),
              habitId: log.habitId,
            ),
          ),
        ];

        final now = normalizeDate(DateTime.now());
        final heatmapStart = now.subtract(const Duration(days: 139));
        final heatmap = notifier.dayProgressRange(
          start: heatmapStart,
          end: now,
        );
        final weekStart = now.subtract(const Duration(days: 6));
        final weeklyProgress = notifier.dayProgressRange(
          start: weekStart,
          end: now,
        );
        final weeklySummary = _WeeklySummary.fromMap(weeklyProgress);

        final grouped = <DateTime, List<_CompletedEntry>>{};
        for (final entry in allEntries) {
          grouped.putIfAbsent(entry.date, () => <_CompletedEntry>[]).add(entry);
        }

        final sortedDates = grouped.keys.toList(growable: false)
          ..sort((a, b) => b.compareTo(a));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            _CompletionHeatmap(
              start: heatmapStart,
              end: now,
              progressByDay: heatmap,
            ),
            const SizedBox(height: 10),
            _WeeklyReflectionCard(summary: weeklySummary),
            const SizedBox(height: 14),
            if (allEntries.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    'Nothing completed yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              )
            else
              ...sortedDates.map((date) {
                final entries = grouped[date]!
                  ..sort(
                    (a, b) =>
                        a.label.toLowerCase().compareTo(b.label.toLowerCase()),
                  );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        formatGroupDate(date),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      ...entries.map(
                        (entry) => _CompletedEntryTile(
                          entry: entry,
                          onUndo: () => _undoEntry(context, ref, entry),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  String _completedTypeLabel(TaskItem task, Map<String, String> projectById) {
    if (task.type != TaskType.milestone) {
      return task.type.label;
    }

    final projectName = projectById[task.projectId]?.trim();
    if (projectName == null || projectName.isEmpty) {
      return 'Milestone';
    }
    return 'Milestone • $projectName';
  }

  Future<void> _undoEntry(
    BuildContext context,
    WidgetRef ref,
    _CompletedEntry entry,
  ) async {
    final notifier = ref.read(appControllerProvider.notifier);

    switch (entry.kind) {
      case _CompletedEntryKind.task:
        if (entry.taskId == null) {
          return;
        }
        await notifier.reopenTask(entry.taskId!);
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved "${entry.label}" back to active')),
        );
        break;
      case _CompletedEntryKind.habitLog:
        if (entry.habitId == null) {
          return;
        }
        await notifier.undoHabitCompletion(
          taskId: entry.habitId!,
          date: entry.date,
        );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Undid habit log for ${entry.label}')),
        );
        break;
    }
  }
}

class _CompletedEntryTile extends StatelessWidget {
  const _CompletedEntryTile({required this.entry, required this.onUndo});

  final _CompletedEntry entry;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        dense: true,
        title: Text(entry.label, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          entry.typeLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: TextButton.icon(
          onPressed: onUndo,
          icon: const Icon(Icons.undo),
          label: const Text('Take back'),
        ),
      ),
    );
  }
}

class _CompletionHeatmap extends StatelessWidget {
  const _CompletionHeatmap({
    required this.start,
    required this.end,
    required this.progressByDay,
  });

  final DateTime start;
  final DateTime end;
  final Map<DateTime, DayProgress> progressByDay;

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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Day Completion Heatmap',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Each square shows how fully that day was completed. Low days stay neutral so recovery feels easy.',
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
                                final inRange =
                                    !day.isBefore(firstDay) &&
                                    !day.isAfter(lastDay);
                                final progress =
                                    progressByDay[day] ??
                                    const DayProgress(
                                      plannedCount: 0,
                                      completedCount: 0,
                                    );

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Tooltip(
                                    message:
                                        '${formatGroupDate(day)} • ${progress.completedCount}/${progress.plannedCount}',
                                    child: Container(
                                      width: 13,
                                      height: 13,
                                      decoration: BoxDecoration(
                                        color: inRange
                                            ? _heatColor(
                                                palette: palette,
                                                progress: progress,
                                              )
                                            : Colors.transparent,
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
            const SizedBox(height: 8),
            Text(
              'Low to high: neutral gray -> accent',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Color _heatColor({
    required GlitchPalette palette,
    required DayProgress progress,
  }) {
    if (!progress.hadAnythingPlanned) {
      return palette.surfaceRaised;
    }

    final ratio = progress.ratio;
    if (ratio <= 0) {
      return palette.surfaceRaised;
    }
    if (ratio < 0.4) {
      return palette.accent.withValues(alpha: 0.22);
    }
    if (ratio < 0.8) {
      return palette.accent.withValues(alpha: 0.6);
    }
    return palette.accent;
  }
}

class _WeeklyReflectionCard extends StatelessWidget {
  const _WeeklyReflectionCard({required this.summary});

  final _WeeklySummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Weekly reflection',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${summary.completed}/${summary.planned} completed this week - ${summary.perfectDays} perfect day(s).',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              summary.message,
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

class _WeeklySummary {
  const _WeeklySummary({
    required this.planned,
    required this.completed,
    required this.perfectDays,
  });

  final int planned;
  final int completed;
  final int perfectDays;

  double get ratio {
    if (planned <= 0) {
      return 0;
    }
    return (completed / planned).clamp(0, 1);
  }

  String get message {
    if (planned == 0) {
      return 'No pressure week. Start tomorrow with one small win.';
    }
    if (ratio >= 0.8) {
      return 'Steady rhythm this week. Keep the same calm pace.';
    }
    if (ratio >= 0.4) {
      return 'Mixed week, still moving forward. Pick one priority for tomorrow.';
    }
    return 'A quiet week can still reset momentum. Plan one easy task next.';
  }

  factory _WeeklySummary.fromMap(Map<DateTime, DayProgress> progressByDay) {
    var planned = 0;
    var completed = 0;
    var perfectDays = 0;

    for (final progress in progressByDay.values) {
      planned += progress.plannedCount;
      completed += progress.completedCount;
      if (progress.isPerfectDay) {
        perfectDays += 1;
      }
    }

    return _WeeklySummary(
      planned: planned,
      completed: completed,
      perfectDays: perfectDays,
    );
  }
}

enum _CompletedEntryKind { task, habitLog }

class _CompletedEntry {
  const _CompletedEntry({
    required this.kind,
    required this.label,
    required this.typeLabel,
    required this.date,
    this.taskId,
    this.habitId,
  });

  final _CompletedEntryKind kind;
  final String label;
  final String typeLabel;
  final DateTime date;
  final String? taskId;
  final String? habitId;
}
