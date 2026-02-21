import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/task.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../shared/state/app_controller.dart';
import 'task_creation_sheet.dart';

class TodayHomeScreen extends ConsumerStatefulWidget {
  const TodayHomeScreen({super.key});

  @override
  ConsumerState<TodayHomeScreen> createState() => _TodayHomeScreenState();
}

class _TodayHomeScreenState extends ConsumerState<TodayHomeScreen> {
  final PageController _pageController = PageController();
  final Map<String, int> _elapsedByTask = <String, int>{};

  Timer? _timer;
  int _pageIndex = 0;
  bool _running = false;
  String? _activeTaskId;

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    final state = ref.watch(appControllerProvider);

    return SafeArea(
      bottom: false,
      child: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) {
          return Center(
            child: Text(
              'Unable to load tasks',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          );
        },
        data: (_) {
          final notifier = ref.read(appControllerProvider.notifier);
          final tasks = notifier.todayTasks(DateTime.now());
          final todayProgress = notifier.dayProgress(DateTime.now());

          if (tasks.isEmpty) {
            _timer?.cancel();
            _running = false;
            _activeTaskId = null;
            final isPerfectDay = todayProgress.isPerfectDay;

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                children: <Widget>[
                  _TopBar(
                    dateLabel: formatReadableDate(DateTime.now()),
                    indexLabel: '0 / 0',
                    onAdd: () {
                      TaskCreationSheet.open(context);
                    },
                  ),
                  const Spacer(),
                  Icon(
                    isPerfectDay
                        ? Icons.auto_awesome_rounded
                        : Icons.wb_incandescent_outlined,
                    size: isPerfectDay ? 54 : 48,
                    color: isPerfectDay
                        ? palette.accent
                        : palette.accent.withValues(alpha: 0.8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isPerfectDay
                        ? 'Perfect day complete'
                        : 'No tasks for today',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isPerfectDay
                        ? 'You completed ${todayProgress.completedCount}/${todayProgress.plannedCount} planned items today.'
                        : 'Add one focused task to start momentum.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (isPerfectDay)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceRaised,
                          border: Border.all(color: palette.surfaceStroke),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Reward earned: On Top of Today',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: palette.accent),
                        ),
                      ),
                    ),
                  if (todayProgress.hadAnythingPlanned)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _EndOfDayRecapCard(
                        progress: todayProgress,
                        onPlanTomorrow: () async {
                          await TaskCreationSheet.open(
                            context,
                            initialType: TaskType.chore,
                            initialScheduledDate: normalizeDate(
                              DateTime.now().add(const Duration(days: 1)),
                            ),
                          );
                        },
                      ),
                    ),
                  const Spacer(),
                ],
              ),
            );
          }

          if (_pageIndex >= tasks.length) {
            _pageIndex = tasks.length - 1;
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              children: <Widget>[
                _TopBar(
                  dateLabel: formatReadableDate(DateTime.now()),
                  indexLabel: '${_pageIndex + 1} / ${tasks.length}',
                  onAdd: () {
                    TaskCreationSheet.open(context);
                  },
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: tasks.length,
                    onPageChanged: (index) {
                      if (index == _pageIndex) {
                        return;
                      }
                      _pauseTimer();
                      setState(() {
                        _pageIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      final elapsed = _durationForTask(task);
                      final targetSeconds = (task.estimatedMinutes ?? 25) * 60;
                      final progress = targetSeconds == 0
                          ? 0.0
                          : (elapsed / targetSeconds).clamp(0.0, 1.0);
                      final habitDoneToday = task.type == TaskType.habit
                          ? notifier.isHabitCompletedOnDate(
                              task.id,
                              DateTime.now(),
                            )
                          : false;
                      final primaryLabel = task.type == TaskType.habit
                          ? (habitDoneToday ? 'Undo Today' : 'Mark Complete')
                          : 'Mark Complete';

                      return _TodayFocusCard(
                        task: task,
                        projectName: notifier.projectNameForId(task.projectId),
                        habitDoneToday: habitDoneToday,
                        habitStreak: notifier.streakForHabit(task.id),
                        habitStreakUnit: notifier.habitStreakUnit(task.id),
                        habitWeeklyCompletions: notifier
                            .habitCompletionsThisWeek(task.id),
                        habitWeeklyTarget: notifier.habitWeeklyTarget(task.id),
                        elapsedSeconds: elapsed,
                        timerProgress: progress,
                        running: _running && _activeTaskId == task.id,
                        targetMinutes: task.estimatedMinutes,
                        primaryLabel: primaryLabel,
                        onToggleTimer: () async {
                          if (_running && _activeTaskId == task.id) {
                            await _pauseTimer();
                          } else {
                            _startTimer(task);
                          }
                        },
                        onPrimaryAction: () async {
                          await _completeTask(
                            task: task,
                            habitDoneToday: habitDoneToday,
                          );
                        },
                        onOverflowAction: (action) async {
                          await _pauseTimer();
                          if (!mounted) {
                            return;
                          }
                          await _handleOverflowAction(action, task);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  int _durationForTask(TaskItem task) {
    final initial = (task.actualMinutes ?? 0) * 60;
    final existing = _elapsedByTask[task.id] ?? initial;
    final merged = existing < initial ? initial : existing;
    _elapsedByTask[task.id] = merged;
    return merged;
  }

  void _startTimer(TaskItem task) {
    _timer?.cancel();
    _activeTaskId = task.id;
    _running = true;

    _elapsedByTask.putIfAbsent(task.id, () => (task.actualMinutes ?? 0) * 60);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _activeTaskId != task.id) {
        return;
      }
      setState(() {
        _elapsedByTask[task.id] = (_elapsedByTask[task.id] ?? 0) + 1;
      });
    });

    setState(() {});
  }

  Future<void> _pauseTimer() async {
    if (!_running) {
      return;
    }

    _timer?.cancel();
    _running = false;

    final activeId = _activeTaskId;
    _activeTaskId = null;

    if (activeId != null) {
      final seconds = _elapsedByTask[activeId] ?? 0;
      final minutes = seconds ~/ 60;
      await ref
          .read(appControllerProvider.notifier)
          .updateTaskDuration(activeId, minutes);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _completeTask({
    required TaskItem task,
    required bool habitDoneToday,
  }) async {
    await _pauseTimer();

    if (task.type == TaskType.habit && habitDoneToday) {
      await ref.read(appControllerProvider.notifier).toggleHabitToday(task.id);
      return;
    }

    final seconds = _durationForTask(task);
    final minutes = seconds ~/ 60;

    await ref
        .read(appControllerProvider.notifier)
        .completeTask(task.id, actualMinutes: minutes);
  }

  Future<void> _confirmDeleteTask(TaskItem task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete task?'),
          content: Text('Delete "${task.title}"?'),
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

    await ref.read(appControllerProvider.notifier).deleteTask(task.id);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Task deleted')));
  }

  Future<void> _handleOverflowAction(
    _TaskOverflowAction action,
    TaskItem task,
  ) async {
    switch (action) {
      case _TaskOverflowAction.edit:
        await TaskCreationSheet.open(context, existingTask: task);
        break;
      case _TaskOverflowAction.delete:
        await _confirmDeleteTask(task);
        break;
    }
  }
}

enum _TaskOverflowAction { edit, delete }

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.dateLabel,
    required this.indexLabel,
    required this.onAdd,
  });

  final String dateLabel;
  final String indexLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;

    return Row(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Today',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              dateLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            border: Border.all(color: palette.surfaceStroke),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            indexLabel,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Add task',
          onPressed: onAdd,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _TodayFocusCard extends StatelessWidget {
  const _TodayFocusCard({
    required this.task,
    required this.projectName,
    required this.habitDoneToday,
    required this.habitStreak,
    required this.habitStreakUnit,
    required this.habitWeeklyCompletions,
    required this.habitWeeklyTarget,
    required this.elapsedSeconds,
    required this.timerProgress,
    required this.running,
    required this.targetMinutes,
    required this.primaryLabel,
    required this.onToggleTimer,
    required this.onPrimaryAction,
    required this.onOverflowAction,
  });

  final TaskItem task;
  final String? projectName;
  final bool habitDoneToday;
  final int habitStreak;
  final String habitStreakUnit;
  final int habitWeeklyCompletions;
  final int habitWeeklyTarget;
  final int elapsedSeconds;
  final double timerProgress;
  final bool running;
  final int? targetMinutes;
  final String primaryLabel;
  final Future<void> Function() onToggleTimer;
  final Future<void> Function() onPrimaryAction;
  final Future<void> Function(_TaskOverflowAction action) onOverflowAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    final normalizedProjectName = projectName?.trim();
    final hasProject =
        normalizedProjectName != null && normalizedProjectName.isNotEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _TaskTypePill(type: task.type),
                if (task.type == TaskType.milestone) ...<Widget>[
                  const SizedBox(width: 8),
                  Flexible(
                    child: _ContextPill(
                      label: hasProject
                          ? 'Project: $normalizedProjectName'
                          : 'Project not set',
                      accent: hasProject ? palette.accent : palette.warning,
                    ),
                  ),
                ],
                const Spacer(),
                if (task.type == TaskType.habit)
                  _ContextPill(
                    label: habitDoneToday ? 'Done today' : 'Pending today',
                    accent: habitDoneToday ? palette.accent : palette.textMuted,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700, height: 1.12),
                    ),
                    if (task.description != null &&
                        task.description!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          task.description!,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: palette.textMuted),
                        ),
                      ),
                    const SizedBox(height: 14),
                    if (task.type == TaskType.habit)
                      Text(
                        habitWeeklyTarget > 0
                            ? '$habitWeeklyCompletions/$habitWeeklyTarget this week • $habitStreak $habitStreakUnit streak'
                            : '$habitStreak $habitStreakUnit streak',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    if (task.type != TaskType.habit &&
                        task.scheduledDate != null)
                      Text(
                        'Due ${formatReadableDate(task.scheduledDate!)}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    if (task.estimatedMinutes != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Estimate ${task.estimatedMinutes} min',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: palette.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.surfaceStroke),
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        CircularProgressIndicator(
                          value: timerProgress,
                          strokeWidth: 7,
                          backgroundColor: palette.surface,
                        ),
                        Text(
                          formatTimer(elapsedSeconds),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          running ? 'Timer running' : 'Timer paused',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          targetMinutes == null
                              ? 'No estimate'
                              : 'Target $targetMinutes min',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textMuted),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 128,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await onToggleTimer();
                            },
                            icon: Icon(
                              running ? Icons.pause : Icons.play_arrow,
                            ),
                            label: Text(running ? 'Pause' : 'Start'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await onPrimaryAction();
                    },
                    child: Text(primaryLabel),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<_TaskOverflowAction>(
                  tooltip: 'Task actions',
                  onSelected: (action) async {
                    await onOverflowAction(action);
                  },
                  itemBuilder: (context) =>
                      const <PopupMenuEntry<_TaskOverflowAction>>[
                        PopupMenuItem<_TaskOverflowAction>(
                          value: _TaskOverflowAction.edit,
                          child: Text('Edit'),
                        ),
                        PopupMenuItem<_TaskOverflowAction>(
                          value: _TaskOverflowAction.delete,
                          child: Text('Delete'),
                        ),
                      ],
                  icon: Icon(Icons.more_vert, color: palette.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskTypePill extends StatelessWidget {
  const _TaskTypePill({required this.type});

  final TaskType type;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    final Color bg;
    switch (type) {
      case TaskType.chore:
        bg = palette.pillChore;
        break;
      case TaskType.habit:
        bg = palette.pillHabit;
        break;
      case TaskType.milestone:
        bg = palette.pillMilestone;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        type.label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: palette.pillText,
        ),
      ),
    );
  }
}

class _ContextPill extends StatelessWidget {
  const _ContextPill({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.surfaceStroke),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }
}

class _EndOfDayRecapCard extends StatelessWidget {
  const _EndOfDayRecapCard({
    required this.progress,
    required this.onPlanTomorrow,
  });

  final DayProgress progress;
  final Future<void> Function() onPlanTomorrow;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    final completionPercent = (progress.ratio * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'End-of-day recap',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${progress.completedCount}/${progress.plannedCount} completed ($completionPercent%).',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Keep momentum by setting one task for tomorrow.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                unawaited(onPlanTomorrow());
              },
              child: const Text('Plan tomorrow'),
            ),
          ],
        ),
      ),
    );
  }
}
