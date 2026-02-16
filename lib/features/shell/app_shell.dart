import 'package:flutter/material.dart';

import '../../core/models/task.dart';
import '../../core/theme/app_theme.dart';
import '../../features/chores/chores_screen.dart';
import '../../features/completed/completed_screen.dart';
import '../../features/habits/habits_screen.dart';
import '../../features/projects/projects_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/tasks/task_creation_sheet.dart';
import '../../features/tasks/today_home_screen.dart';

enum AppSection { today, chores, habits, projects, completed, settings }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection _currentSection = AppSection.today;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentSection == AppSection.today
          ? null
          : AppBar(title: Text(_titleFor(_currentSection))),
      body: IndexedStack(
        index: _currentSection.index,
        children: const <Widget>[
          TodayHomeScreen(),
          ChoresScreen(),
          HabitsScreen(),
          ProjectsScreen(),
          CompletedScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _BottomNavigation(
        current: _currentSection,
        onChanged: (section) {
          setState(() {
            _currentSection = section;
          });
        },
      ),
      floatingActionButton: _fabForSection(context),
    );
  }

  Widget? _fabForSection(BuildContext context) {
    switch (_currentSection) {
      case AppSection.today:
        return FloatingActionButton(
          onPressed: () => TaskCreationSheet.open(context),
          child: const Icon(Icons.add),
        );
      case AppSection.chores:
        return FloatingActionButton.extended(
          onPressed: () =>
              TaskCreationSheet.open(context, initialType: TaskType.chore),
          icon: const Icon(Icons.add),
          label: const Text('Chore'),
        );
      case AppSection.habits:
        return FloatingActionButton.extended(
          onPressed: () =>
              TaskCreationSheet.open(context, initialType: TaskType.habit),
          icon: const Icon(Icons.add),
          label: const Text('Habit'),
        );
      case AppSection.projects:
        return FloatingActionButton.extended(
          onPressed: () =>
              TaskCreationSheet.open(context, initialType: TaskType.milestone),
          icon: const Icon(Icons.add),
          label: const Text('Milestone'),
        );
      case AppSection.completed:
      case AppSection.settings:
        return null;
    }
  }

  String _titleFor(AppSection section) {
    return switch (section) {
      AppSection.today => 'Today',
      AppSection.chores => 'Chores',
      AppSection.habits => 'Habits',
      AppSection.projects => 'Projects',
      AppSection.completed => 'Completed',
      AppSection.settings => 'Settings',
    };
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({required this.current, required this.onChanged});

  final AppSection current;
  final ValueChanged<AppSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.surfaceStroke),
        ),
        child: Row(
          children:
              <_NavItemData>[
                    const _NavItemData(
                      section: AppSection.today,
                      icon: Icons.today_outlined,
                      selectedIcon: Icons.today,
                      label: 'Today',
                    ),
                    const _NavItemData(
                      section: AppSection.chores,
                      icon: Icons.checklist_outlined,
                      selectedIcon: Icons.checklist,
                      label: 'Chores',
                    ),
                    const _NavItemData(
                      section: AppSection.habits,
                      icon: Icons.repeat_outlined,
                      selectedIcon: Icons.repeat,
                      label: 'Habits',
                    ),
                    const _NavItemData(
                      section: AppSection.projects,
                      icon: Icons.work_outline,
                      selectedIcon: Icons.work,
                      label: 'Projects',
                    ),
                    const _NavItemData(
                      section: AppSection.completed,
                      icon: Icons.check_circle_outline,
                      selectedIcon: Icons.check_circle,
                      label: 'Done',
                    ),
                    const _NavItemData(
                      section: AppSection.settings,
                      icon: Icons.tune_outlined,
                      selectedIcon: Icons.tune,
                      label: 'Settings',
                    ),
                  ]
                  .map((item) {
                    return Expanded(
                      child: _NavButton(
                        data: item,
                        selected: current == item.section,
                        onTap: () => onChanged(item.section),
                      ),
                    );
                  })
                  .toList(growable: false),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _NavItemData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? palette.surfaceRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: selected ? Border.all(color: palette.surfaceStroke) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              selected ? data.selectedIcon : data.icon,
              color: selected ? palette.accent : palette.textMuted,
              size: 20,
            ),
            const SizedBox(height: 2),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? palette.textPrimary : palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItemData {
  const _NavItemData({
    required this.section,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final AppSection section;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
