import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/project.dart';
import '../../core/models/task.dart';
import '../../core/theme/app_theme.dart';
import '../../features/tasks/task_creation_sheet.dart';
import '../../shared/state/app_controller.dart';
import 'project_creation_sheet.dart';

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);

    return state.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) =>
          const Scaffold(body: Center(child: Text('Unable to load project'))),
      data: (_) {
        final notifier = ref.read(appControllerProvider.notifier);
        final project = notifier
            .projects()
            .where((item) => item.id == projectId)
            .toList();

        if (project.isEmpty) {
          return const Scaffold(body: Center(child: Text('Project not found')));
        }

        final current = project.first;
        final milestones = notifier.milestonesForProject(projectId);
        final palette = context.glitchPalette;

        return Scaffold(
          appBar: AppBar(
            title: Text(current.name),
            actions: <Widget>[
              IconButton(
                tooltip: 'Edit project',
                onPressed: () {
                  ProjectCreationSheet.open(context, existingProject: current);
                },
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Delete project',
                onPressed: () => _confirmDeleteProject(context, ref, current),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: <Widget>[
              if (current.description != null &&
                  current.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    current.description!,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              Text(
                'Milestones',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (milestones.isEmpty)
                Text(
                  'No milestones yet.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                ),
              ...milestones.map((milestone) {
                return Card(
                  child: ListTile(
                    title: Text(milestone.title),
                    subtitle: Text(
                      milestone.completed ? 'Completed' : 'In progress',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (milestone.completed)
                          Icon(Icons.check_circle, color: palette.accent),
                        PopupMenuButton<_MilestoneAction>(
                          tooltip: 'Milestone actions',
                          onSelected: (action) {
                            switch (action) {
                              case _MilestoneAction.edit:
                                TaskCreationSheet.open(
                                  context,
                                  fixedProjectId: projectId,
                                  existingTask: milestone,
                                );
                                break;
                              case _MilestoneAction.delete:
                                _confirmDeleteMilestone(
                                  context,
                                  ref,
                                  milestone,
                                );
                                break;
                            }
                          },
                          itemBuilder: (context) =>
                              const <PopupMenuEntry<_MilestoneAction>>[
                                PopupMenuItem<_MilestoneAction>(
                                  value: _MilestoneAction.edit,
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem<_MilestoneAction>(
                                  value: _MilestoneAction.delete,
                                  child: Text('Delete'),
                                ),
                              ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              TaskCreationSheet.open(
                context,
                initialType: TaskType.milestone,
                fixedProjectId: projectId,
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Add milestone'),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteProject(
    BuildContext context,
    WidgetRef ref,
    ProjectItem project,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete project?'),
          content: Text(
            'Deleting "${project.name}" will remove all milestones in this project.',
          ),
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

    await ref.read(appControllerProvider.notifier).deleteProject(project.id);

    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text('Deleted ${project.name}')));
  }

  Future<void> _confirmDeleteMilestone(
    BuildContext context,
    WidgetRef ref,
    TaskItem milestone,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete milestone?'),
          content: Text('Delete "${milestone.title}" from this project?'),
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

    await ref.read(appControllerProvider.notifier).deleteTask(milestone.id);

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Milestone deleted')));
  }
}

enum _MilestoneAction { edit, delete }
