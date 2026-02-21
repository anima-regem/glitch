import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../chores/chores_screen.dart';
import '../habits/habits_screen.dart';
import '../projects/projects_screen.dart';

enum ListsTab { chores, habits, projects }

class ListsHubScreen extends StatefulWidget {
  const ListsHubScreen({super.key});

  @override
  State<ListsHubScreen> createState() => _ListsHubScreenState();
}

class _ListsHubScreenState extends State<ListsHubScreen> {
  ListsTab _currentTab = ListsTab.chores;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Lists',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Switch between chores, habits, and projects without leaving focus mode.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<ListsTab>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      side: WidgetStateProperty.resolveWith<BorderSide>((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return BorderSide(
                            color: palette.accent.withValues(alpha: 0.5),
                          );
                        }
                        return BorderSide(color: palette.surfaceStroke);
                      }),
                      backgroundColor: WidgetStateProperty.resolveWith<Color>((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return palette.accent.withValues(alpha: 0.16);
                        }
                        return palette.surface;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith<Color>((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return palette.textPrimary;
                        }
                        return palette.textMuted;
                      }),
                      textStyle: WidgetStatePropertyAll<TextStyle?>(
                        Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    segments: const <ButtonSegment<ListsTab>>[
                      ButtonSegment<ListsTab>(
                        value: ListsTab.chores,
                        icon: Icon(Icons.checklist_outlined),
                        label: Text('Chores'),
                      ),
                      ButtonSegment<ListsTab>(
                        value: ListsTab.habits,
                        icon: Icon(Icons.repeat_outlined),
                        label: Text('Habits'),
                      ),
                      ButtonSegment<ListsTab>(
                        value: ListsTab.projects,
                        icon: Icon(Icons.work_outline),
                        label: Text('Projects'),
                      ),
                    ],
                    selected: <ListsTab>{_currentTab},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) {
                        return;
                      }
                      setState(() {
                        _currentTab = selection.first;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _currentTab.index,
            children: const <Widget>[
              ChoresScreen(),
              HabitsScreen(),
              ProjectsScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
