import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/task.dart';
import '../../core/services/task_audio_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';

class TaskCard extends ConsumerStatefulWidget {
  const TaskCard({
    super.key,
    required this.task,
    this.projectName,
    required this.habitCompletedToday,
    required this.habitStreak,
    required this.habitStreakUnit,
    required this.habitWeeklyCompletions,
    required this.habitWeeklyTarget,
    required this.habitCompletionDates,
  });

  final TaskItem task;
  final String? projectName;
  final bool habitCompletedToday;
  final int habitStreak;
  final String habitStreakUnit;
  final int habitWeeklyCompletions;
  final int habitWeeklyTarget;
  final List<DateTime> habitCompletionDates;

  @override
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard> {
  bool _playingAudio = false;

  Future<void> _playTaskAudio() async {
    if (_playingAudio) {
      return;
    }
    setState(() => _playingAudio = true);
    try {
      await ref.read(taskAudioServiceProvider).speakTaskText(
            title: widget.task.title,
            description: widget.task.description,
          );
    } finally {
      if (mounted) {
        setState(() => _playingAudio = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    final task = widget.task;
    final projectName = widget.projectName?.trim();
    final hasProjectName = projectName != null && projectName.isNotEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _TypePill(type: task.type),
                if (task.type == TaskType.milestone) ...<Widget>[
                  const SizedBox(width: 8),
                  Flexible(
                    child: _ContextPill(
                      label: hasProjectName
                          ? 'Project: $projectName'
                          : 'Project not set',
                      accent: hasProjectName ? palette.accent : palette.warning,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            task.title,
                            softWrap: true,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.12,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: _playingAudio
                              ? 'Playing audio...'
                              : 'Play source audio',
                          onPressed: _playingAudio ? null : _playTaskAudio,
                          icon: Icon(
                            _playingAudio ? Icons.volume_up : Icons.play_arrow,
                          ),
                        ),
                      ],
                    ),
                    if (task.description != null &&
                        task.description!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          task.description!,
                          softWrap: true,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: palette.textMuted),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (task.type == TaskType.habit)
                      _HabitDetails(
                        recurrence: task.recurrence,
                        completedToday: widget.habitCompletedToday,
                        streak: widget.habitStreak,
                        streakUnit: widget.habitStreakUnit,
                        weeklyCompletions: widget.habitWeeklyCompletions,
                        weeklyTarget: widget.habitWeeklyTarget,
                        completionDates: widget.habitCompletionDates,
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
          ],
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
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.type});

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

class _HabitDetails extends StatelessWidget {
  const _HabitDetails({
    required this.recurrence,
    required this.completedToday,
    required this.streak,
    required this.streakUnit,
    required this.weeklyCompletions,
    required this.weeklyTarget,
    required this.completionDates,
  });

  final HabitRecurrence? recurrence;
  final bool completedToday;
  final int streak;
  final String streakUnit;
  final int weeklyCompletions;
  final int weeklyTarget;
  final List<DateTime> completionDates;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    final now = normalizeDate(DateTime.now());
    final last56 = List<DateTime>.generate(
      56,
      (index) => now.subtract(Duration(days: 55 - index)),
      growable: false,
    );

    final completionSet = completionDates.map(normalizeDate).toSet();
    final isWeeklyTargetMode = recurrence?.usesTimesPerWeek == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: <Widget>[
            Text(
              isWeeklyTargetMode
                  ? '$weeklyCompletions/$weeklyTarget this week'
                  : (completedToday ? 'Completed today' : 'Pending today'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: palette.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '$streak $streakUnit streak',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 114,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: last56.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              final day = last56[index];
              final done = completionSet.contains(day);

              return Container(
                decoration: BoxDecoration(
                  color: done ? palette.accent : palette.surfaceRaised,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
