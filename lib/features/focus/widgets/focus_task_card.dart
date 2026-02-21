import 'package:flutter/material.dart';

import '../../../core/models/task.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_time_utils.dart';

enum FocusTaskMenuAction { edit, delete }

class FocusTaskCard extends StatelessWidget {
  const FocusTaskCard({
    super.key,
    required this.task,
    required this.projectName,
    required this.elapsedSeconds,
    required this.timerProgress,
    required this.running,
    required this.targetMinutes,
    required this.habitDoneToday,
    required this.habitStreak,
    required this.habitStreakUnit,
    required this.habitWeeklyCompletions,
    required this.habitWeeklyTarget,
    required this.actions,
  });

  final TaskItem task;
  final String? projectName;
  final int elapsedSeconds;
  final double timerProgress;
  final bool running;
  final int? targetMinutes;
  final bool habitDoneToday;
  final int habitStreak;
  final String habitStreakUnit;
  final int habitWeeklyCompletions;
  final int habitWeeklyTarget;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    final textTheme = Theme.of(context).textTheme;
    final normalizedProjectName = projectName?.trim();
    final hasProject =
        normalizedProjectName != null && normalizedProjectName.isNotEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _Badge(
                  label: task.type.label,
                  color: _taskTypeColor(task.type, palette),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasProject
                        ? normalizedProjectName
                        : _taskContextLabel(task),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
                if (task.type == TaskType.habit)
                  _StatusPill(
                    label: habitDoneToday ? 'Done today' : 'Pending today',
                    color: habitDoneToday ? palette.accent : palette.textMuted,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              task.title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _MetaChip(
                  label: task.priority.label,
                  icon: Icons.flag_outlined,
                ),
                _MetaChip(label: task.effort.label, icon: Icons.bolt_outlined),
                _MetaChip(
                  label: task.energyWindow.label,
                  icon: Icons.wb_sunny_outlined,
                ),
                if (task.estimatedMinutes != null)
                  _MetaChip(
                    label: '${task.estimatedMinutes}m target',
                    icon: Icons.schedule_outlined,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.surfaceStroke),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _descriptionText(task),
                        style: textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                          height: 1.35,
                        ),
                      ),
                      if (task.type == TaskType.habit)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            habitWeeklyTarget > 0
                                ? '$habitWeeklyCompletions/$habitWeeklyTarget this week • $habitStreak $habitStreakUnit streak'
                                : '$habitStreak $habitStreakUnit streak',
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                      if (task.type != TaskType.habit &&
                          task.scheduledDate != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Due ${formatReadableDate(task.scheduledDate!)}',
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 112,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.surfaceStroke),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 84,
                        height: 84,
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
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              running ? 'Timer running' : 'Timer paused',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _timerSubtitle(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...actions,
          ],
        ),
      ),
    );
  }

  String _descriptionText(TaskItem task) {
    final description = task.description?.trim();
    if (description != null && description.isNotEmpty) {
      return description;
    }

    if (task.type == TaskType.habit && task.recurrence != null) {
      return 'Recurring: ${task.recurrence!.label}';
    }

    if (task.scheduledDate != null) {
      return 'Scheduled ${formatReadableDate(task.scheduledDate!)}';
    }

    return 'No extra notes. Keep it simple and complete one action.';
  }

  String _taskContextLabel(TaskItem task) {
    if (task.type == TaskType.milestone) {
      return 'Project milestone';
    }
    if (task.type == TaskType.habit) {
      return 'Habit loop';
    }
    return 'Single-focus task';
  }

  String _timerSubtitle() {
    if (targetMinutes == null) {
      return 'No estimate set';
    }
    return 'Target $targetMinutes min';
  }

  Color _taskTypeColor(TaskType type, GlitchPalette palette) {
    switch (type) {
      case TaskType.chore:
        return palette.pillChore;
      case TaskType.habit:
        return palette.pillHabit;
      case TaskType.milestone:
        return palette.pillMilestone;
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: palette.pillText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.16),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.surfaceStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: palette.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}
