import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/task.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../shared/state/app_controller.dart';
import '../tasks/task_creation_sheet.dart';

class ChoresScreen extends ConsumerWidget {
  const ChoresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('Failed to load chores')),
      data: (_) {
        final notifier = ref.read(appControllerProvider.notifier);
        final chores = notifier.allChores();

        if (chores.isEmpty) {
          return Center(
            child: Text(
              'No active chores',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: chores.length,
          separatorBuilder: (_, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final chore = chores[index];
            return _ChoreCard(chore: chore);
          },
        );
      },
    );
  }
}

class _ChoreCard extends ConsumerWidget {
  const _ChoreCard({required this.chore});

  final TaskItem chore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.glitchPalette;
    final dueLabel = _dueLabel(chore);

    return Card(
      child: ListTile(
        onTap: () => TaskCreationSheet.open(context, existingTask: chore),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(
          chore.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 2),
            Text(
              dueLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _isOverdue(chore) ? palette.warning : palette.textMuted,
              ),
            ),
            if (chore.description != null &&
                chore.description!.trim().isNotEmpty)
              Text(
                chore.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            if (chore.estimatedMinutes != null)
              Text(
                'Estimate ${chore.estimatedMinutes} min',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
          ],
        ),
        leading: IconButton(
          tooltip: 'Mark complete',
          icon: Icon(Icons.check_circle_outline, color: palette.accent),
          onPressed: () async {
            await ref
                .read(appControllerProvider.notifier)
                .completeTask(chore.id);
            if (!context.mounted) {
              return;
            }
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Chore completed')));
          },
        ),
        trailing: PopupMenuButton<_ChoreAction>(
          tooltip: 'Chore actions',
          onSelected: (action) async {
            switch (action) {
              case _ChoreAction.edit:
                await TaskCreationSheet.open(context, existingTask: chore);
                break;
              case _ChoreAction.delete:
                await _confirmDelete(context, ref, chore);
                break;
            }
          },
          itemBuilder: (context) => const <PopupMenuEntry<_ChoreAction>>[
            PopupMenuItem<_ChoreAction>(
              value: _ChoreAction.edit,
              child: Text('Edit'),
            ),
            PopupMenuItem<_ChoreAction>(
              value: _ChoreAction.delete,
              child: Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  String _dueLabel(TaskItem task) {
    final date = task.scheduledDate;
    if (date == null) {
      return 'No due date';
    }

    final today = normalizeDate(DateTime.now());
    final normalized = normalizeDate(date);

    if (isSameDay(normalized, today)) {
      return 'Due today';
    }
    if (normalized.isBefore(today)) {
      return 'Overdue since ${formatReadableDate(normalized)}';
    }
    return 'Due ${formatReadableDate(normalized)}';
  }

  bool _isOverdue(TaskItem task) {
    final date = task.scheduledDate;
    if (date == null) {
      return false;
    }
    return normalizeDate(date).isBefore(normalizeDate(DateTime.now()));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete chore?'),
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

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Chore deleted')));
  }
}

enum _ChoreAction { edit, delete }
