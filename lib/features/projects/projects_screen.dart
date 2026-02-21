import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/project.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/state/app_controller.dart';
import 'project_creation_sheet.dart';
import 'project_detail_screen.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('Failed to load projects')),
      data: (_) {
        final notifier = ref.read(appControllerProvider.notifier);
        final projects = notifier.projects();
        final palette = context.glitchPalette;

        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Build by milestones',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Each project tracks active milestones and completion in real time.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => ProjectCreationSheet.open(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Create project'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: projects.isEmpty
                  ? _EmptyProjects(
                      onCreate: () => ProjectCreationSheet.open(context),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemBuilder: (context, index) {
                        final project = projects[index];
                        final progress = notifier.projectProgress(project.id);
                        final activeMilestones = notifier.activeMilestoneCount(
                          project.id,
                        );

                        return _ProjectCard(
                          name: project.name,
                          description: project.description,
                          progress: progress,
                          activeMilestones: activeMilestones,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    ProjectDetailScreen(projectId: project.id),
                              ),
                            );
                          },
                          onEdit: () {
                            ProjectCreationSheet.open(
                              context,
                              existingProject: project,
                            );
                          },
                          onDelete: () {
                            _confirmDeleteProject(context, ref, project);
                          },
                        );
                      },
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 10),
                      itemCount: projects.length,
                    ),
            ),
          ],
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
            'Deleting "${project.name}" will remove its milestones too.',
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Deleted ${project.name}')));
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.name,
    required this.description,
    required this.progress,
    required this.activeMilestones,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final String name;
  final String? description;
  final int progress;
  final int activeMilestones;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  PopupMenuButton<_ProjectCardAction>(
                    tooltip: 'Project actions',
                    onSelected: (value) {
                      switch (value) {
                        case _ProjectCardAction.edit:
                          onEdit();
                          break;
                        case _ProjectCardAction.delete:
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (context) =>
                        const <PopupMenuEntry<_ProjectCardAction>>[
                          PopupMenuItem<_ProjectCardAction>(
                            value: _ProjectCardAction.edit,
                            child: Text('Edit'),
                          ),
                          PopupMenuItem<_ProjectCardAction>(
                            value: _ProjectCardAction.delete,
                            child: Text('Delete'),
                          ),
                        ],
                  ),
                ],
              ),
              if (description != null && description!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                  ),
                ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress / 100),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    '$progress% complete',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    '•',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: palette.textMuted),
                  ),
                  Text(
                    '$activeMilestones active milestones',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ProjectCardAction { edit, delete }

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.layers_outlined, size: 44, color: palette.accent),
            const SizedBox(height: 10),
            Text(
              'No projects yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Create your first project, then add milestones to track progress.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create project'),
            ),
          ],
        ),
      ),
    );
  }
}
