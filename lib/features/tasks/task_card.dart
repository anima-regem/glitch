import 'package:flutter/material.dart';

import '../../core/models/task.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';

class TaskCard extends StatefulWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.habitCompletedToday,
    required this.habitStreak,
    required this.habitStreakUnit,
    required this.habitWeeklyCompletions,
    required this.habitWeeklyTarget,
    required this.habitCompletionDates,
  });

  final TaskItem task;
  final bool habitCompletedToday;
  final int habitStreak;
  final String habitStreakUnit;
  final int habitWeeklyCompletions;
  final int habitWeeklyTarget;
  final List<DateTime> habitCompletionDates;

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _expandedDescription = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    final task = widget.task;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _TypePill(type: task.type),
            const SizedBox(height: 18),
            Text(
              task.title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.08,
              ),
            ),
            if (task.description != null && task.description!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      task.description!,
                      maxLines: _expandedDescription ? null : 2,
                      overflow: _expandedDescription
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => setState(
                        () => _expandedDescription = !_expandedDescription,
                      ),
                      child: Text(
                        _expandedDescription ? 'Hide' : 'Show details',
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
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
            if (task.type != TaskType.habit && task.scheduledDate != null)
              Text(
                'Due ${formatReadableDate(task.scheduledDate!)}',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: palette.textMuted),
              ),
            if (task.estimatedMinutes != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Estimate ${task.estimatedMinutes} min',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: palette.textMuted),
                ),
              ),
          ],
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
        Row(
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
            const SizedBox(width: 12),
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
