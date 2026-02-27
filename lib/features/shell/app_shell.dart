import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/models/app_data.dart';
import '../../core/models/task.dart';
import '../../core/services/storage_permission_service.dart';
import '../../core/theme/app_theme.dart';
import '../../features/backup/passphrase_prompt.dart';
import '../../features/completed/completed_screen.dart';
import '../../features/focus/focus_screen.dart';
import '../../features/lists/lists_hub_screen.dart';
import '../../features/projects/project_creation_sheet.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/migration_recovery_screen.dart';
import '../../features/tasks/task_creation_sheet.dart';
import '../../shared/state/app_controller.dart';

enum AppSection { focus, lists, done, settings }

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  AppSection _currentSection = AppSection.focus;
  bool _backupPromptShownThisSession = false;
  bool _backupPromptDeferredThisSession = false;
  final StoragePermissionService _storagePermissionService =
      const StoragePermissionService();

  void _maybePromptBackupVault(AppData data) {
    final prefs = data.preferences;
    if (_backupPromptShownThisSession) {
      return;
    }

    final configuredPath = prefs.backupVaultPath?.trim();
    if (prefs.backupVaultPromptDismissed ||
        (configuredPath != null && configuredPath.isNotEmpty)) {
      _backupPromptShownThisSession = true;
      return;
    }

    final hasActivationMilestone = _hasActivationMilestone(data);
    final reachedSecondOpen = prefs.backupPromptDeferrals >= 1;
    if (!hasActivationMilestone && _backupPromptDeferredThisSession) {
      return;
    }

    if (!hasActivationMilestone && !reachedSecondOpen) {
      if (!_backupPromptDeferredThisSession) {
        _backupPromptDeferredThisSession = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          unawaited(
            ref
                .read(appControllerProvider.notifier)
                .incrementBackupPromptDeferrals(),
          );
        });
      }
      return;
    }

    _backupPromptShownThisSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await _showBackupVaultGetStarted();
    });
  }

  bool _hasActivationMilestone(AppData data) {
    final hasCompletedTasks = data.tasks.any((task) => task.completed);
    final hasCompletedHabitLogs = data.habitLogs.any((log) => log.completed);
    return hasCompletedTasks || hasCompletedHabitLogs;
  }

  Future<void> _showBackupVaultGetStarted() async {
    final action = await showDialog<_BackupVaultPromptAction>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('Protect data across uninstall'),
          content: const Text(
            'Set a backup vault folder to keep encrypted snapshots outside app storage. This helps recovery after uninstall or device migration.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(_BackupVaultPromptAction.later);
              },
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(_BackupVaultPromptAction.setupNow);
              },
              child: const Text('Set up now'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (action == null) {
      return;
    }

    if (action != _BackupVaultPromptAction.setupNow) {
      await ref
          .read(appControllerProvider.notifier)
          .setBackupVaultPromptDismissed();
      return;
    }

    final hasPermission = await _ensureStoragePermission();
    if (!hasPermission || !mounted) {
      return;
    }

    String? directory;
    try {
      directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select backup vault folder',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Folder picker failed: $error')));
      return;
    }

    if (directory == null || !mounted) {
      return;
    }

    final passphrase = await showBackupPassphraseDialog(
      context: context,
      title: 'Set vault passphrase',
      description:
          'This passphrase encrypts your vault snapshot and is required to restore on another device.',
      confirmPassphrase: true,
    );
    if (passphrase == null || !mounted) {
      return;
    }

    try {
      await ref
          .read(appControllerProvider.notifier)
          .configureBackupVault(
            directoryPath: directory,
            passphrase: passphrase,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup vault configured at $directory')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup vault setup failed: $error')),
      );
    }
  }

  Future<bool> _ensureStoragePermission() async {
    final permission = await _storagePermissionService
        .ensureStoragePermissionForFolderAccess();
    if (permission.granted || !mounted) {
      return permission.granted;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(permission.message),
        action: permission.canOpenSettings
            ? SnackBarAction(
                label: 'Settings',
                onPressed: () {
                  openAppSettings();
                },
              )
            : null,
      ),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appControllerProvider);
    final data = appState.valueOrNull;
    final controller = ref.read(appControllerProvider.notifier);
    if (data != null) {
      _maybePromptBackupVault(data);
    }
    final migrationFailure = controller.hasMigrationFailure
        ? (controller.migrationFailureReason ?? 'Unknown migration error.')
        : null;

    if (migrationFailure != null) {
      return Scaffold(
        body: MigrationRecoveryScreen(failureReason: migrationFailure),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _currentSection.index,
        children: const <Widget>[
          FocusScreen(),
          ListsHubScreen(),
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
    );
  }

  PreferredSizeWidget? _buildAppBar() {
    if (_currentSection == AppSection.focus) {
      return null;
    }

    final palette = context.glitchPalette;
    final actions = switch (_currentSection) {
      AppSection.lists => <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 10),
          child: Material(
            color: palette.accent,
            shadowColor: palette.accent.withValues(alpha: 0.5),
            shape: const CircleBorder(),
            elevation: 3,
            child: IconButton(
              key: const Key('lists_appbar_add_button'),
              tooltip: 'Add item',
              onPressed: _showListsCreateMenu,
              icon: Icon(Icons.add, color: palette.amoled),
            ),
          ),
        ),
      ],
      AppSection.done ||
      AppSection.settings ||
      AppSection.focus => const <Widget>[],
    };

    return AppBar(title: Text(_titleFor(_currentSection)), actions: actions);
  }

  Future<void> _showListsCreateMenu() async {
    final action = await showModalBottomSheet<_ListCreateAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(
                title: Text('Create from Lists'),
                subtitle: Text('Choose what you want to add'),
              ),
              ListTile(
                leading: const Icon(Icons.checklist_outlined),
                title: const Text('Chore'),
                onTap: () {
                  Navigator.of(context).pop(_ListCreateAction.chore);
                },
              ),
              ListTile(
                leading: const Icon(Icons.repeat_outlined),
                title: const Text('Habit'),
                onTap: () {
                  Navigator.of(context).pop(_ListCreateAction.habit);
                },
              ),
              ListTile(
                leading: const Icon(Icons.work_outline),
                title: const Text('Milestone'),
                onTap: () {
                  Navigator.of(context).pop(_ListCreateAction.milestone);
                },
              ),
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('Project'),
                onTap: () {
                  Navigator.of(context).pop(_ListCreateAction.project);
                },
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _ListCreateAction.chore:
        await TaskCreationSheet.open(context, initialType: TaskType.chore);
        break;
      case _ListCreateAction.habit:
        await TaskCreationSheet.open(context, initialType: TaskType.habit);
        break;
      case _ListCreateAction.milestone:
        final projects = ref.read(appControllerProvider.notifier).projects();
        if (projects.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Create a project first so milestones have a clear home.',
              ),
            ),
          );
          await ProjectCreationSheet.open(context);
          return;
        }
        await TaskCreationSheet.open(context, initialType: TaskType.milestone);
        break;
      case _ListCreateAction.project:
        await ProjectCreationSheet.open(context);
        break;
    }
  }

  String _titleFor(AppSection section) {
    return switch (section) {
      AppSection.focus => 'Focus',
      AppSection.lists => 'Lists',
      AppSection.done => 'Done',
      AppSection.settings => 'Settings',
    };
  }
}

enum _BackupVaultPromptAction { setupNow, later }

enum _ListCreateAction { chore, habit, milestone, project }

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
                      section: AppSection.focus,
                      icon: Icons.self_improvement_outlined,
                      selectedIcon: Icons.self_improvement,
                      label: 'Focus',
                    ),
                    const _NavItemData(
                      section: AppSection.lists,
                      icon: Icons.checklist_outlined,
                      selectedIcon: Icons.checklist,
                      label: 'Lists',
                    ),
                    const _NavItemData(
                      section: AppSection.done,
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
