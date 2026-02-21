import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/project.dart';
import '../../core/models/task.dart';
import '../../core/theme/app_theme.dart';
import '../projects/project_creation_sheet.dart';
import '../../shared/state/app_controller.dart';

class TaskCreationSheet extends ConsumerStatefulWidget {
  const TaskCreationSheet({
    super.key,
    this.initialType,
    this.initialScheduledDate,
    this.fixedProjectId,
    this.existingTask,
  });

  final TaskType? initialType;
  final DateTime? initialScheduledDate;
  final String? fixedProjectId;
  final TaskItem? existingTask;

  bool get isEditing => existingTask != null;

  static Future<void> open(
    BuildContext context, {
    TaskType? initialType,
    DateTime? initialScheduledDate,
    String? fixedProjectId,
    TaskItem? existingTask,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: TaskCreationSheet(
            initialType: initialType,
            initialScheduledDate: initialScheduledDate,
            fixedProjectId: fixedProjectId,
            existingTask: existingTask,
          ),
        );
      },
    );
  }

  @override
  ConsumerState<TaskCreationSheet> createState() => _TaskCreationSheetState();
}

class _TaskCreationSheetState extends ConsumerState<TaskCreationSheet> {
  static const List<int> _weekdayOrder = <int>[
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  ];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _estimateController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _descriptionFocusNode = FocusNode();

  late TaskType _selectedType;
  DateTime? _selectedDate;
  late HabitRecurrenceType _recurrenceType;
  Set<int> _selectedWeekdays = <int>{};
  int _timesPerWeek = 3;
  String? _projectId;
  late TaskPriority _priority;
  late TaskEffort _effort;
  late TaskEnergyWindow _energyWindow;
  bool _saving = false;
  String? _titleError;

  bool get _hasValidTitle => _titleController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _descriptionFocusNode.addListener(_handleDescriptionFocusChanged);

    final task = widget.existingTask;
    _selectedType = task?.type ?? widget.initialType ?? TaskType.chore;
    _selectedDate = _selectedType == TaskType.habit
        ? task?.scheduledDate
        : (task?.scheduledDate ??
              widget.initialScheduledDate ??
              DateTime.now());

    final recurrence = task?.recurrence ?? HabitRecurrence.daily();
    _recurrenceType = recurrence.type;
    _selectedWeekdays = recurrence.daysOfWeek.toSet();
    _timesPerWeek = recurrence.timesPerWeek ?? 3;
    if (_selectedWeekdays.isEmpty) {
      _selectedWeekdays = <int>{DateTime.monday};
    }

    _projectId = widget.fixedProjectId ?? task?.projectId;
    _priority = task?.priority ?? TaskPriority.medium;
    _effort = task?.effort ?? TaskEffort.light;
    _energyWindow = task?.energyWindow ?? TaskEnergyWindow.any;

    _titleController.text = task?.title ?? '';
    _descriptionController.text = task?.description ?? '';
    if (task?.estimatedMinutes != null) {
      _estimateController.text = task!.estimatedMinutes.toString();
    }
  }

  @override
  void dispose() {
    _descriptionFocusNode.removeListener(_handleDescriptionFocusChanged);
    _descriptionFocusNode.dispose();
    _scrollController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _estimateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appControllerProvider).valueOrNull;
    final projects = appState?.projects ?? const <ProjectItem>[];
    final palette = context.glitchPalette;

    final noProjectsAvailable =
        _selectedType == TaskType.milestone &&
        widget.fixedProjectId == null &&
        projects.isEmpty;
    final milestoneMissingProject =
        _selectedType == TaskType.milestone &&
        widget.fixedProjectId == null &&
        _projectId == null;
    final invalidHabitRecurrence =
        _selectedType == TaskType.habit &&
        _recurrenceType == HabitRecurrenceType.specificDays &&
        _selectedWeekdays.isEmpty;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.isEditing ? 'Edit task' : 'Add task',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onChanged: (_) {
                if (_titleError != null || _saving) {
                  setState(() {
                    _titleError = null;
                  });
                  return;
                }
                setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: 'What needs focus?',
                errorText: _titleError,
              ),
            ),
            const SizedBox(height: 12),
            if (!widget.isEditing)
              DropdownButtonFormField<TaskType>(
                key: ValueKey<String>('type-${_selectedType.name}'),
                initialValue: _selectedType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: TaskType.values
                    .map(
                      (type) => DropdownMenuItem<TaskType>(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedType = value;
                    if (_selectedType == TaskType.habit) {
                      _selectedDate = null;
                      _projectId = null;
                    } else {
                      _selectedDate ??=
                          widget.initialScheduledDate ?? DateTime.now();
                      if (_selectedType != TaskType.milestone) {
                        _projectId = null;
                      }
                    }
                  });
                },
              )
            else
              Card(
                child: ListTile(
                  leading: const Icon(Icons.label_outline),
                  title: const Text('Task type'),
                  subtitle: Text(_selectedType.label),
                ),
              ),
            const SizedBox(height: 12),
            if (_selectedType == TaskType.habit) ...<Widget>[
              DropdownButtonFormField<HabitRecurrenceType>(
                key: ValueKey<String>(
                  'recurrence-type-${_recurrenceType.name}',
                ),
                initialValue: _recurrenceType,
                decoration: const InputDecoration(labelText: 'Habit schedule'),
                items: HabitRecurrenceType.values
                    .map(
                      (value) => DropdownMenuItem<HabitRecurrenceType>(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _recurrenceType = value;
                    if (_recurrenceType == HabitRecurrenceType.specificDays &&
                        _selectedWeekdays.isEmpty) {
                      _selectedWeekdays = <int>{DateTime.monday};
                    }
                  });
                },
              ),
              if (_recurrenceType ==
                  HabitRecurrenceType.specificDays) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  'Specific days',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _weekdayOrder
                      .map((weekday) {
                        final selected = _selectedWeekdays.contains(weekday);
                        return FilterChip(
                          selected: selected,
                          onSelected: (enabled) {
                            setState(() {
                              if (enabled) {
                                _selectedWeekdays.add(weekday);
                              } else {
                                _selectedWeekdays.remove(weekday);
                              }
                            });
                          },
                          label: Text(
                            HabitRecurrence.shortWeekdayLabel(weekday),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
                if (_selectedWeekdays.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Select at least one day.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                  ),
              ],
              if (_recurrenceType ==
                  HabitRecurrenceType.timesPerWeek) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  '${_timesPerWeek.toString()} days each week',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Slider(
                  value: _timesPerWeek.toDouble(),
                  min: 1,
                  max: 7,
                  divisions: 6,
                  label: _timesPerWeek.toString(),
                  onChanged: (value) {
                    setState(() {
                      _timesPerWeek = value.round();
                    });
                  },
                ),
                Text(
                  'You can complete on any days until the weekly target is met.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ],
            ],
            if (_selectedType != TaskType.habit)
              Card(
                child: ListTile(
                  title: const Text('Scheduled date'),
                  subtitle: Text(
                    _selectedDate == null
                        ? 'Select date'
                        : MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(_selectedDate!),
                  ),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final today = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: today.subtract(const Duration(days: 365 * 2)),
                      lastDate: today.add(const Duration(days: 365 * 5)),
                      initialDate: _selectedDate ?? today,
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                    }
                  },
                ),
              ),
            if (_selectedType == TaskType.milestone)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 12),
                  if (!noProjectsAvailable)
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'project-${widget.fixedProjectId ?? _projectId ?? 'none'}-${projects.length}',
                      ),
                      initialValue: widget.fixedProjectId ?? _projectId,
                      decoration: const InputDecoration(labelText: 'Project'),
                      items: projects
                          .map(
                            (project) => DropdownMenuItem<String>(
                              value: project.id,
                              child: Text(
                                project.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: widget.fixedProjectId != null
                          ? null
                          : (value) => setState(() => _projectId = value),
                    ),
                  if (noProjectsAvailable)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Card(
                        color: palette.surfaceRaised,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Milestones need a project',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Create a project first so this milestone has clear ownership.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: palette.textMuted),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: _createProjectAndSelect,
                                icon: const Icon(Icons.add),
                                label: const Text('Create project'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (!noProjectsAvailable && milestoneMissingProject)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Select a project to continue.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: palette.warning),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _estimateController,
              keyboardType: TextInputType.number,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                labelText: 'Estimated minutes',
                hintText: 'Optional',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<TaskPriority>(
                    key: ValueKey<String>('priority-${_priority.name}'),
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: TaskPriority.values
                        .map(
                          (value) => DropdownMenuItem<TaskPriority>(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _priority = value);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<TaskEffort>(
                    key: ValueKey<String>('effort-${_effort.name}'),
                    initialValue: _effort,
                    decoration: const InputDecoration(labelText: 'Effort'),
                    items: TaskEffort.values
                        .map(
                          (value) => DropdownMenuItem<TaskEffort>(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _effort = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TaskEnergyWindow>(
              key: ValueKey<String>('energy-${_energyWindow.name}'),
              initialValue: _energyWindow,
              decoration: const InputDecoration(labelText: 'Energy window'),
              items: TaskEnergyWindow.values
                  .map(
                    (value) => DropdownMenuItem<TaskEnergyWindow>(
                      value: value,
                      child: Text(value.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _energyWindow = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              focusNode: _descriptionFocusNode,
              minLines: 3,
              maxLines: 5,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              scrollPadding: const EdgeInsets.only(bottom: 180),
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Optional context',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    (_saving ||
                        !_hasValidTitle ||
                        milestoneMissingProject ||
                        invalidHabitRecurrence)
                    ? null
                    : _submit,
                child: Text(
                  _saving
                      ? (widget.isEditing ? 'Saving...' : 'Creating...')
                      : (widget.isEditing ? 'Save changes' : 'Create task'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  HabitRecurrence _buildRecurrence() {
    switch (_recurrenceType) {
      case HabitRecurrenceType.daily:
        return HabitRecurrence.daily();
      case HabitRecurrenceType.specificDays:
        return HabitRecurrence.specificDays(_selectedWeekdays);
      case HabitRecurrenceType.timesPerWeek:
        return HabitRecurrence.timesPerWeek(_timesPerWeek);
    }
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _titleError = 'Title is required.';
      });
      return;
    }

    if (_selectedType == TaskType.milestone &&
        widget.fixedProjectId == null &&
        _projectId == null) {
      return;
    }

    setState(() {
      _saving = true;
      _titleError = null;
    });

    final estimate = int.tryParse(_estimateController.text.trim());
    final notifier = ref.read(appControllerProvider.notifier);
    final recurrence = _selectedType == TaskType.habit
        ? _buildRecurrence()
        : null;

    if (widget.existingTask != null) {
      await notifier.updateTask(
        taskId: widget.existingTask!.id,
        title: title,
        description: _descriptionController.text,
        scheduledDate: _selectedDate,
        recurrence: recurrence,
        estimatedMinutes: estimate,
        projectId: widget.fixedProjectId ?? _projectId,
        priority: _priority,
        effort: _effort,
        energyWindow: _energyWindow,
      );
    } else {
      await notifier.addTask(
        title: title,
        type: _selectedType,
        description: _descriptionController.text,
        scheduledDate: _selectedDate,
        recurrence: recurrence,
        estimatedMinutes: estimate,
        projectId: widget.fixedProjectId ?? _projectId,
        priority: _priority,
        effort: _effort,
        energyWindow: _energyWindow,
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _createProjectAndSelect() async {
    await ProjectCreationSheet.open(context);
    if (!mounted) {
      return;
    }

    final projects = ref.read(appControllerProvider.notifier).projects();
    if (projects.isEmpty) {
      return;
    }

    final selectedProjectId = widget.fixedProjectId ?? _projectId;
    if (selectedProjectId != null &&
        projects.any((project) => project.id == selectedProjectId)) {
      return;
    }

    setState(() {
      _projectId = projects.first.id;
    });
  }

  void _handleDescriptionFocusChanged() {
    if (!_descriptionFocusNode.hasFocus) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
}
