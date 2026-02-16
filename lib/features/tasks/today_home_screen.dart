import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/task.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../shared/state/app_controller.dart';
import 'task_card.dart';
import 'task_creation_sheet.dart';

class TodayHomeScreen extends ConsumerStatefulWidget {
  const TodayHomeScreen({super.key});

  @override
  ConsumerState<TodayHomeScreen> createState() => _TodayHomeScreenState();
}

class _TodayHomeScreenState extends ConsumerState<TodayHomeScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.9);
  final Map<String, int> _elapsedByTask = <String, int>{};

  Timer? _timer;
  int _pageIndex = 0;
  bool _running = false;
  String? _activeTaskId;
  bool _milestoneGlitch = false;

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
                  const Spacer(),
                ],
              ),
            );
          }

          if (_pageIndex >= tasks.length) {
            _pageIndex = tasks.length - 1;
          }

          final currentTask = tasks[_pageIndex];
          final elapsed = _durationForTask(currentTask);
          final targetSeconds = (currentTask.estimatedMinutes ?? 25) * 60;
          final progress = targetSeconds == 0
              ? 0.0
              : (elapsed / targetSeconds).clamp(0.0, 1.0);

          final habitDoneToday = currentTask.type == TaskType.habit
              ? notifier.isHabitCompletedOnDate(currentTask.id, DateTime.now())
              : false;

          final primaryLabel = currentTask.type == TaskType.habit
              ? (habitDoneToday ? 'Undo Today' : 'Mark Complete')
              : 'Mark Complete';

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              children: <Widget>[
                _TopBar(
                  dateLabel: formatReadableDate(DateTime.now()),
                  indexLabel: '${_pageIndex + 1} / ${tasks.length}',
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
                      final isVisible = index == _pageIndex;
                      return AnimatedScale(
                        duration: const Duration(milliseconds: 220),
                        scale: isVisible ? 1 : 0.96,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            transform: Matrix4.translationValues(
                              isVisible && _milestoneGlitch ? 4 : 0,
                              0,
                              0,
                            ),
                            child: TaskCard(
                              task: task,
                              habitCompletedToday: notifier
                                  .isHabitCompletedOnDate(
                                    task.id,
                                    DateTime.now(),
                                  ),
                              habitStreak: notifier.streakForHabit(task.id),
                              habitStreakUnit: notifier.habitStreakUnit(
                                task.id,
                              ),
                              habitWeeklyCompletions: notifier
                                  .habitCompletionsThisWeek(task.id),
                              habitWeeklyTarget: notifier.habitWeeklyTarget(
                                task.id,
                              ),
                              habitCompletionDates: notifier
                                  .completionDatesForHabit(task.id),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                _TimerBlock(
                  elapsedSeconds: elapsed,
                  progress: progress,
                  running: _running && _activeTaskId == currentTask.id,
                  targetMinutes: currentTask.estimatedMinutes,
                  onToggle: () {
                    if (_running && _activeTaskId == currentTask.id) {
                      _pauseTimer();
                    } else {
                      _startTimer(currentTask);
                    }
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _completeTask(
                      task: currentTask,
                      habitDoneToday: habitDoneToday,
                    ),
                    child: Text(primaryLabel),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _pauseTimer();
                          if (!context.mounted) {
                            return;
                          }
                          await TaskCreationSheet.open(
                            context,
                            existingTask: currentTask,
                          );
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () async {
                          await _pauseTimer();
                          await _confirmDeleteTask(currentTask);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
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
      final minutes = (seconds / 60).ceil();
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
    final minutes = (seconds / 60).ceil();

    if (task.type == TaskType.milestone) {
      HapticFeedback.selectionClick();
      setState(() => _milestoneGlitch = true);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (mounted) {
        setState(() => _milestoneGlitch = false);
      }
    }

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
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.dateLabel, required this.indexLabel});

  final String dateLabel;
  final String indexLabel;

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
      ],
    );
  }
}

class _TimerBlock extends StatelessWidget {
  const _TimerBlock({
    required this.elapsedSeconds,
    required this.progress,
    required this.running,
    required this.targetMinutes,
    required this.onToggle,
  });

  final int elapsedSeconds;
  final double progress;
  final bool running;
  final int? targetMinutes;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 110,
          height: 110,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 8,
                backgroundColor: palette.surfaceRaised,
              ),
              Text(
                formatTimer(elapsedSeconds),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: onToggle,
              icon: Icon(running ? Icons.pause : Icons.play_arrow),
              label: Text(running ? 'Pause' : 'Start'),
            ),
            const SizedBox(height: 8),
            Text(
              targetMinutes == null
                  ? 'No estimate'
                  : 'Target $targetMinutes min',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}
