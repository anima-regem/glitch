import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/task.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../shared/state/app_controller.dart';
import '../tasks/task_creation_sheet.dart';
import 'focus_run_screen.dart';
import 'widgets/focus_task_card.dart';

class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  final PageController _pageController = PageController();
  final Map<String, int> _elapsedByTask = <String, int>{};

  Timer? _timer;
  String? _runningTaskId;
  int _pageIndex = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appControllerProvider);
    final palette = context.glitchPalette;

    return SafeArea(
      bottom: false,
      child: appState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Unable to load focus tasks')),
        data: (_) {
          final notifier = ref.read(appControllerProvider.notifier);
          final tasks = notifier.todayTasks(
            DateTime.now(),
            includeOverdue: true,
          );
          final progress = notifier.dayProgress(DateTime.now());

          if (tasks.isEmpty) {
            _pauseRunningTimer(persist: false);
            _pageIndex = 0;
            return _EmptyFocusState(
              progress: progress,
              onCreateTask: () {
                TaskCreationSheet.open(context, initialType: TaskType.chore);
              },
              onPlanTomorrow: () async {
                await TaskCreationSheet.open(
                  context,
                  initialType: TaskType.chore,
                  initialScheduledDate: normalizeDate(
                    DateTime.now().add(const Duration(days: 1)),
                  ),
                );
              },
            );
          }

          final clampedIndex = _pageIndex.clamp(0, tasks.length - 1);
          if (clampedIndex != _pageIndex) {
            _pageIndex = clampedIndex;
            _syncPageControllerToIndex();
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              children: <Widget>[
                _FocusHeader(
                  dateLabel: formatReadableDate(DateTime.now()),
                  indexLabel: '${_pageIndex + 1} / ${tasks.length}',
                  runningTaskId: _runningTaskId,
                  onCreateTask: () {
                    TaskCreationSheet.open(
                      context,
                      initialType: TaskType.chore,
                    );
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
                      _pauseRunningTimer(persist: true);
                      setState(() {
                        _pageIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      final elapsed = _durationForTask(task);
                      final targetSeconds = (task.estimatedMinutes ?? 25) * 60;
                      final progressRatio = targetSeconds == 0
                          ? 0.0
                          : (elapsed / targetSeconds).clamp(0.0, 1.0);
                      final habitDoneToday = task.type == TaskType.habit
                          ? notifier.isHabitCompletedOnDate(
                              task.id,
                              DateTime.now(),
                            )
                          : false;
                      final primaryLabel = task.type == TaskType.habit
                          ? (habitDoneToday ? 'Undo today' : 'Mark complete')
                          : 'Mark complete';

                      return AnimatedScale(
                        duration: context.motion(AppMotionTokens.fast),
                        curve: AppMotionTokens.enterCurve,
                        scale: index == _pageIndex ? 1 : 0.98,
                        child: FocusTaskCard(
                          task: task,
                          projectName: notifier.projectNameForId(
                            task.projectId,
                          ),
                          elapsedSeconds: elapsed,
                          timerProgress: progressRatio,
                          running: _runningTaskId == task.id,
                          targetMinutes: task.estimatedMinutes,
                          habitDoneToday: habitDoneToday,
                          habitStreak: notifier.streakForHabit(task.id),
                          habitStreakUnit: notifier.habitStreakUnit(task.id),
                          habitWeeklyCompletions: notifier
                              .habitCompletionsThisWeek(task.id),
                          habitWeeklyTarget: notifier.habitWeeklyTarget(
                            task.id,
                          ),
                          actions: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () async {
                                      await _openRunMode(
                                        task: task,
                                        primaryLabel: primaryLabel,
                                        habitDoneToday: habitDoneToday,
                                      );
                                    },
                                    icon: const Icon(Icons.fullscreen),
                                    label: Text(
                                      _runningTaskId == task.id
                                          ? 'Open running focus'
                                          : 'Start focus',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<FocusTaskMenuAction>(
                                  tooltip: 'Task actions',
                                  onSelected: (action) async {
                                    await _handleOverflowAction(action, task);
                                  },
                                  itemBuilder: (context) =>
                                      const <
                                        PopupMenuEntry<FocusTaskMenuAction>
                                      >[
                                        PopupMenuItem<FocusTaskMenuAction>(
                                          value: FocusTaskMenuAction.edit,
                                          child: Text('Edit'),
                                        ),
                                        PopupMenuItem<FocusTaskMenuAction>(
                                          value: FocusTaskMenuAction.delete,
                                          child: Text('Delete'),
                                        ),
                                      ],
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    child: Icon(Icons.more_horiz),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () async {
                                  await _handlePrimaryAction(
                                    task: task,
                                    habitDoneToday: habitDoneToday,
                                    elapsedSeconds: elapsed,
                                  );
                                },
                                child: Text(primaryLabel),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Swipe left or right to move between tasks',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  int _durationForTask(TaskItem task) {
    final persistedSeconds = (task.actualMinutes ?? 0) * 60;
    final inMemory = _elapsedByTask[task.id] ?? persistedSeconds;
    final merged = max(inMemory, persistedSeconds);
    _elapsedByTask[task.id] = merged;
    return merged;
  }

  void _startRunningTimer({
    required String taskId,
    required int initialElapsedSeconds,
  }) {
    _timer?.cancel();
    _runningTaskId = taskId;
    final merged = max(_elapsedByTask[taskId] ?? 0, initialElapsedSeconds);
    _elapsedByTask[taskId] = merged;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _runningTaskId != taskId) {
        return;
      }
      setState(() {
        _elapsedByTask[taskId] = (_elapsedByTask[taskId] ?? 0) + 1;
      });
    });

    if (mounted) {
      setState(() {});
    }
  }

  void _pauseRunningTimer({required bool persist}) {
    final runningTaskId = _runningTaskId;
    if (runningTaskId == null) {
      return;
    }

    _timer?.cancel();
    _runningTaskId = null;

    if (persist) {
      final elapsed = _elapsedByTask[runningTaskId] ?? 0;
      final minutes = elapsed ~/ 60;
      unawaited(
        ref
            .read(appControllerProvider.notifier)
            .updateTaskDuration(runningTaskId, minutes),
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openRunMode({
    required TaskItem task,
    required String primaryLabel,
    required bool habitDoneToday,
  }) async {
    if (_runningTaskId != null && _runningTaskId != task.id) {
      _pauseRunningTimer(persist: true);
    }

    if (_runningTaskId == task.id) {
      _pauseRunningTimer(persist: false);
    }

    final notifier = ref.read(appControllerProvider.notifier);
    final elapsed = _durationForTask(task);

    final result = await Navigator.of(context).push<FocusRunResult>(
      MaterialPageRoute<FocusRunResult>(
        builder: (_) {
          return FocusRunScreen(
            task: task,
            projectName: notifier.projectNameForId(task.projectId),
            initialElapsedSeconds: elapsed,
            habitDoneToday: habitDoneToday,
            habitStreak: notifier.streakForHabit(task.id),
            habitStreakUnit: notifier.habitStreakUnit(task.id),
            habitWeeklyCompletions: notifier.habitCompletionsThisWeek(task.id),
            habitWeeklyTarget: notifier.habitWeeklyTarget(task.id),
            targetMinutes: task.estimatedMinutes,
            primaryLabel: primaryLabel,
          );
        },
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    _elapsedByTask[result.taskId] = max(
      _elapsedByTask[result.taskId] ?? 0,
      result.elapsedSeconds,
    );

    final latestTasks = notifier.todayTasks(
      DateTime.now(),
      includeOverdue: true,
    );
    final active = _taskById(latestTasks, result.taskId);

    if (result.requestedDelete) {
      if (active == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task is no longer available.')),
        );
        return;
      }
      await notifier.deleteTask(active.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Task deleted')));
      return;
    }

    if (result.requestedEdit) {
      if (active == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task is no longer available.')),
        );
        return;
      }
      await TaskCreationSheet.open(context, existingTask: active);
      return;
    }

    if (result.primaryActionRequested) {
      if (active == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task is no longer available.')),
        );
        return;
      }
      await _handlePrimaryAction(
        task: active,
        habitDoneToday: result.habitDoneAtLaunch,
        elapsedSeconds: result.elapsedSeconds,
      );
      return;
    }

    if (result.running) {
      final stillVisible =
          _taskById(
            notifier.todayTasks(DateTime.now(), includeOverdue: true),
            result.taskId,
          ) !=
          null;
      if (stillVisible) {
        _startRunningTimer(
          taskId: result.taskId,
          initialElapsedSeconds: result.elapsedSeconds,
        );
      }
    }
  }

  Future<void> _handlePrimaryAction({
    required TaskItem task,
    required bool habitDoneToday,
    required int elapsedSeconds,
  }) async {
    _pauseRunningTimer(persist: false);

    final notifier = ref.read(appControllerProvider.notifier);

    if (task.type == TaskType.habit && habitDoneToday) {
      await notifier.toggleHabitToday(task.id);
      return;
    }

    final minutes = max(0, elapsedSeconds ~/ 60);
    await notifier.completeTask(task.id, actualMinutes: minutes);

    final refreshed = notifier.todayTasks(DateTime.now(), includeOverdue: true);
    final maxIndex = max(0, refreshed.length - 1);
    if (_pageIndex > maxIndex) {
      setState(() {
        _pageIndex = maxIndex;
      });
      _syncPageControllerToIndex();
    }
  }

  Future<void> _handleOverflowAction(
    FocusTaskMenuAction action,
    TaskItem task,
  ) async {
    _pauseRunningTimer(persist: true);

    switch (action) {
      case FocusTaskMenuAction.edit:
        await TaskCreationSheet.open(context, existingTask: task);
        break;
      case FocusTaskMenuAction.delete:
        await _confirmDeleteTask(task);
        break;
    }
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

  TaskItem? _taskById(List<TaskItem> tasks, String taskId) {
    for (final task in tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  void _syncPageControllerToIndex() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) {
        return;
      }
      final currentPage = (_pageController.page ?? _pageIndex.toDouble())
          .round();
      if (currentPage == _pageIndex) {
        return;
      }
      _pageController.jumpToPage(_pageIndex);
    });
  }
}

class _FocusHeader extends StatelessWidget {
  const _FocusHeader({
    required this.dateLabel,
    required this.indexLabel,
    required this.runningTaskId,
    required this.onCreateTask,
  });

  final String dateLabel;
  final String indexLabel;
  final String? runningTaskId;
  final VoidCallback onCreateTask;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Focus',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                dateLabel,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
        if (runningTaskId != null)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Running',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: palette.accent),
            ),
          ),
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
          onPressed: onCreateTask,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _EmptyFocusState extends StatelessWidget {
  const _EmptyFocusState({
    required this.progress,
    required this.onCreateTask,
    required this.onPlanTomorrow,
  });

  final DayProgress progress;
  final VoidCallback onCreateTask;
  final Future<void> Function() onPlanTomorrow;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    final isPerfectDay = progress.isPerfectDay;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _FocusHeader(
            dateLabel: formatReadableDate(DateTime.now()),
            indexLabel: '0 / 0',
            runningTaskId: null,
            onCreateTask: onCreateTask,
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
            isPerfectDay ? 'Perfect day complete' : 'No tasks for today',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            isPerfectDay
                ? 'You completed ${progress.completedCount}/${progress.plannedCount} planned items today.'
                : 'Add one focused task to start momentum.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onCreateTask,
            icon: const Icon(Icons.add),
            label: const Text('Create task'),
          ),
          if (progress.hadAnythingPlanned)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await onPlanTomorrow();
                },
                icon: const Icon(Icons.event_note_outlined),
                label: const Text('Plan tomorrow'),
              ),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}
