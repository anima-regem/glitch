import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glitch/core/utils/date_time_utils.dart';

import '../../core/models/task.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/focus_task_card.dart';

enum FocusRunMenuAction { edit, delete }

class FocusRunResult {
  const FocusRunResult({
    required this.taskId,
    required this.elapsedSeconds,
    required this.running,
    this.primaryActionRequested = false,
    this.requestedEdit = false,
    this.requestedDelete = false,
    this.habitDoneAtLaunch = false,
  });

  final String taskId;
  final int elapsedSeconds;
  final bool running;
  final bool primaryActionRequested;
  final bool requestedEdit;
  final bool requestedDelete;
  final bool habitDoneAtLaunch;
}

class FocusRunScreen extends StatefulWidget {
  const FocusRunScreen({
    super.key,
    required this.task,
    required this.projectName,
    required this.initialElapsedSeconds,
    required this.habitDoneToday,
    required this.habitStreak,
    required this.habitStreakUnit,
    required this.habitWeeklyCompletions,
    required this.habitWeeklyTarget,
    required this.targetMinutes,
    required this.primaryLabel,
  });

  final TaskItem task;
  final String? projectName;
  final int initialElapsedSeconds;
  final bool habitDoneToday;
  final int habitStreak;
  final String habitStreakUnit;
  final int habitWeeklyCompletions;
  final int habitWeeklyTarget;
  final int? targetMinutes;
  final String primaryLabel;

  @override
  State<FocusRunScreen> createState() => _FocusRunScreenState();
}

class _FocusRunScreenState extends State<FocusRunScreen> {
  Timer? _timer;
  late int _elapsedSeconds;
  bool _running = true;
  bool _showCelebration = false;

  @override
  void initState() {
    super.initState();
    _elapsedSeconds = max(0, widget.initialElapsedSeconds);
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetSeconds = (widget.targetMinutes ?? 25) * 60;
    final timerProgress = targetSeconds == 0
        ? 0.0
        : (_elapsedSeconds / targetSeconds).clamp(0.0, 1.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _closeWithResult(
          FocusRunResult(
            taskId: widget.task.id,
            elapsedSeconds: _elapsedSeconds,
            running: _running,
            habitDoneAtLaunch: widget.habitDoneToday,
          ),
        );
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close focus mode',
            onPressed: () {
              _closeWithResult(
                FocusRunResult(
                  taskId: widget.task.id,
                  elapsedSeconds: _elapsedSeconds,
                  running: _running,
                  habitDoneAtLaunch: widget.habitDoneToday,
                ),
              );
            },
            icon: const Icon(Icons.close),
          ),
          title: const Text('Focus run'),
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final panelHeight = min(
                  380.0,
                  max(190.0, constraints.maxHeight * 0.42),
                ).toDouble();

                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        SizedBox(
                          height: panelHeight,
                          child: Center(
                            child: _FullscreenTimerPanel(
                              elapsedSeconds: _elapsedSeconds,
                              timerProgress: timerProgress,
                              running: _running,
                              targetMinutes: widget.targetMinutes,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: FocusTaskCard(
                            task: widget.task,
                            projectName: widget.projectName,
                            elapsedSeconds: _elapsedSeconds,
                            timerProgress: timerProgress,
                            running: _running,
                            targetMinutes: widget.targetMinutes,
                            habitDoneToday: widget.habitDoneToday,
                            habitStreak: widget.habitStreak,
                            habitStreakUnit: widget.habitStreakUnit,
                            habitWeeklyCompletions:
                                widget.habitWeeklyCompletions,
                            habitWeeklyTarget: widget.habitWeeklyTarget,
                            showTimerSection: false,
                            actions: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () {
                                        if (_running) {
                                          _pauseTimer();
                                        } else {
                                          _startTimer();
                                        }
                                      },
                                      icon: Icon(
                                        _running
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                      ),
                                      label: Text(
                                        _running ? 'Pause' : 'Resume',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  PopupMenuButton<FocusRunMenuAction>(
                                    tooltip: 'Task actions',
                                    onSelected: (value) {
                                      switch (value) {
                                        case FocusRunMenuAction.edit:
                                          _pauseTimer();
                                          _closeWithResult(
                                            FocusRunResult(
                                              taskId: widget.task.id,
                                              elapsedSeconds: _elapsedSeconds,
                                              running: false,
                                              requestedEdit: true,
                                              habitDoneAtLaunch:
                                                  widget.habitDoneToday,
                                            ),
                                          );
                                          break;
                                        case FocusRunMenuAction.delete:
                                          _pauseTimer();
                                          _closeWithResult(
                                            FocusRunResult(
                                              taskId: widget.task.id,
                                              elapsedSeconds: _elapsedSeconds,
                                              running: false,
                                              requestedDelete: true,
                                              habitDoneAtLaunch:
                                                  widget.habitDoneToday,
                                            ),
                                          );
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) =>
                                        const <
                                          PopupMenuEntry<FocusRunMenuAction>
                                        >[
                                          PopupMenuItem<FocusRunMenuAction>(
                                            value: FocusRunMenuAction.edit,
                                            child: Text('Edit'),
                                          ),
                                          PopupMenuItem<FocusRunMenuAction>(
                                            value: FocusRunMenuAction.delete,
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
                                  onPressed: _onPrimaryAction,
                                  child: Text(widget.primaryLabel),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    _CelebrationLayer(visible: _showCelebration),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _running = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_running) {
        return;
      }
      setState(() {
        _elapsedSeconds += 1;
      });
    });
    if (mounted) {
      setState(() {});
    }
  }

  void _pauseTimer() {
    _timer?.cancel();
    _running = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onPrimaryAction() async {
    _pauseTimer();
    final shouldCelebrate =
        !(widget.task.type == TaskType.habit &&
            widget.habitDoneToday &&
            widget.primaryLabel.toLowerCase().contains('undo'));

    if (shouldCelebrate) {
      HapticFeedback.lightImpact();
      setState(() {
        _showCelebration = true;
      });
      await Future<void>.delayed(
        context.motion(const Duration(milliseconds: 760)),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _showCelebration = false;
      });
    }

    if (!mounted) {
      return;
    }

    _closeWithResult(
      FocusRunResult(
        taskId: widget.task.id,
        elapsedSeconds: _elapsedSeconds,
        running: false,
        primaryActionRequested: true,
        habitDoneAtLaunch: widget.habitDoneToday,
      ),
    );
  }

  void _closeWithResult(FocusRunResult result) {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(result);
  }
}

class _FullscreenTimerPanel extends StatelessWidget {
  const _FullscreenTimerPanel({
    required this.elapsedSeconds,
    required this.timerProgress,
    required this.running,
    required this.targetMinutes,
  });

  final int elapsedSeconds;
  final double timerProgress;
  final bool running;
  final int? targetMinutes;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    return AnimatedScale(
      duration: const Duration(milliseconds: 300),
      scale: running ? 1 : 0.97,
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 260),
        opacity: running ? 1 : 0.85,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: palette.surface.withValues(alpha: 0.6),
            border: Border.all(color: palette.surfaceStroke),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, timerBox) {
                          final diameter = min(
                            timerBox.maxWidth,
                            timerBox.maxHeight,
                          ).clamp(72.0, 300.0).toDouble();
                          final ringSize = max(
                            48.0,
                            diameter - (diameter >= 220 ? 20 : 16),
                          );
                          final strokeWidth = diameter >= 220 ? 16.0 : 12.0;

                          return Center(
                            child: SizedBox(
                              width: diameter,
                              height: diameter,
                              child: Stack(
                                alignment: Alignment.center,
                                children: <Widget>[
                                  SizedBox(
                                    width: ringSize,
                                    height: ringSize,
                                    child: CircularProgressIndicator(
                                      value: timerProgress,
                                      strokeWidth: strokeWidth,
                                      backgroundColor: palette.surfaceRaised,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        formatTimer(elapsedSeconds),
                                        style: Theme.of(context)
                                            .textTheme
                                            .displayMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      running ? 'Timer running' : 'Timer paused',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      targetMinutes == null
                          ? 'No estimate set'
                          : 'Target $targetMinutes min',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CelebrationLayer extends StatelessWidget {
  const _CelebrationLayer({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;

    return IgnorePointer(
      ignoring: true,
      child: AnimatedOpacity(
        duration: context.motion(AppMotionTokens.base),
        opacity: visible ? 1 : 0,
        child: Container(
          color: palette.accent.withValues(alpha: 0.08),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.surfaceStroke),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.check_circle_outline, color: palette.accent),
                const SizedBox(width: 6),
                const Text('Completed'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
