import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_preferences.dart';
import '../../core/models/project.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/state/app_controller.dart';
import '../../shared/widgets/voice_typing_text_field.dart';

class ProjectCreationSheet extends ConsumerStatefulWidget {
  const ProjectCreationSheet({super.key, this.existingProject});

  final ProjectItem? existingProject;

  bool get isEditing => existingProject != null;

  static Future<void> open(
    BuildContext context, {
    ProjectItem? existingProject,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.78,
          child: ProjectCreationSheet(existingProject: existingProject),
        );
      },
    );
  }

  @override
  ConsumerState<ProjectCreationSheet> createState() =>
      _ProjectCreationSheetState();
}

class _ProjectCreationSheetState extends ConsumerState<ProjectCreationSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final project = widget.existingProject;
    _nameController.text = project?.name ?? '';
    _descriptionController.text = project?.description ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appControllerProvider).valueOrNull;
    final prefs = appState?.preferences ?? AppPreferences.defaults();
    final palette = context.glitchPalette;
    final hasName = _nameController.text.trim().isNotEmpty;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.isEditing ? 'Edit project' : 'Create project',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isEditing
                ? 'Update the project details. Milestones stay linked automatically.'
                : 'Projects group milestones and track completion over time.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 16),
          VoiceTypingTextField(
            controller: _nameController,
            voiceTypingEnabled: prefs.voiceTypingEnabled,
            allowNetworkFallback: prefs.voiceTypingAllowNetworkFallback,
            onAllowNetworkFallbackChanged: (value) {
              return ref
                  .read(appControllerProvider.notifier)
                  .setVoiceTypingAllowNetworkFallback(value);
            },
            textInputAction: TextInputAction.next,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Project name',
              hintText: 'e.g. Mobile portfolio redesign',
            ),
          ),
          const SizedBox(height: 12),
          VoiceTypingTextField(
            controller: _descriptionController,
            voiceTypingEnabled: prefs.voiceTypingEnabled,
            allowNetworkFallback: prefs.voiceTypingAllowNetworkFallback,
            onAllowNetworkFallbackChanged: (value) {
              return ref
                  .read(appControllerProvider.notifier)
                  .setVoiceTypingAllowNetworkFallback(value);
            },
            maxLines: 3,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Optional context',
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(Icons.timeline, color: palette.accent),
              title: Text(
                widget.isEditing ? 'Project progress' : 'After creation',
              ),
              subtitle: Text(
                widget.isEditing
                    ? 'Milestones and completion percentages update live.'
                    : 'Add milestones in project details and track progress automatically.',
              ),
            ),
          ),
          if (_saving) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_saving || !hasName) ? null : _submit,
              child: Text(
                _saving
                    ? (widget.isEditing ? 'Saving...' : 'Creating...')
                    : (widget.isEditing ? 'Save changes' : 'Create project'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }

    setState(() => _saving = true);
    final notifier = ref.read(appControllerProvider.notifier);

    if (widget.existingProject != null) {
      await notifier.updateProject(
        projectId: widget.existingProject!.id,
        name: name,
        description: _descriptionController.text,
      );
    } else {
      await notifier.addProject(
        name: name,
        description: _descriptionController.text,
      );
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.isEditing ? 'Project updated' : 'Project created'),
      ),
    );
  }
}
