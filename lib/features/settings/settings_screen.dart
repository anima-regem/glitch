import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/app_preferences.dart';
import '../../core/services/storage_permission_service.dart';
import '../../core/theme/app_theme.dart';
import '../../features/backup/backup_restore_screen.dart';
import '../../features/backup/passphrase_prompt.dart';
import '../../shared/state/app_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const String _githubUrl = 'https://github.com/anima-regem/glitch';
  static const String _updatesUrl =
      'https://github.com/anima-regem/glitch/releases/latest';
  static const String _buyCoffeeUrl = 'https://buymeacoffee.com/vichukartha';
  static const String _buyCoffeeQrUrl =
      'https://quickchart.io/qr?size=420&text=https%3A%2F%2Fbuymeacoffee.com%2Fvichukartha';

  bool _vaultBusy = false;
  bool _sendingTestReminder = false;
  bool? _lastReminderTestSuccess;
  String? _lastReminderTestMessage;
  String _appName = 'Glitch';
  String _appVersionLabel = 'Version unknown';
  String _packageName = '';
  final StoragePermissionService _storagePermissionService =
      const StoragePermissionService();

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('Failed to load settings')),
      data: (data) {
        final palette = context.glitchPalette;
        final prefs = data.preferences;
        final vaultPath = prefs.backupVaultPath;
        final hasVaultPath = vaultPath != null && vaultPath.trim().isNotEmpty;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            _sectionHeader(context, 'Appearance'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: prefs.useDarkMode,
                      onChanged: (value) {
                        ref
                            .read(appControllerProvider.notifier)
                            .setDarkMode(value);
                      },
                      title: const Text('Dark mode'),
                      subtitle: const Text('AMOLED-first palette by default.'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Dark style',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: DarkThemeStyle.values
                          .map(
                            (style) => ChoiceChip(
                              label: Text(style.label),
                              selected: prefs.darkThemeStyle == style,
                              onSelected: (_) {
                                ref
                                    .read(appControllerProvider.notifier)
                                    .setDarkThemeStyle(style);
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: prefs.highContrast,
                      onChanged: (value) {
                        ref
                            .read(appControllerProvider.notifier)
                            .setHighContrast(value);
                      },
                      title: const Text('High contrast'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Text size',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Slider(
                      value: prefs.textScale,
                      min: 1,
                      max: 1.35,
                      divisions: 7,
                      label: prefs.textScale.toStringAsFixed(2),
                      onChanged: (value) {
                        ref
                            .read(appControllerProvider.notifier)
                            .setTextScale(value);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _sectionHeader(context, 'Focus & Nudges'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Low-frequency reminders stay opt-in.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: prefs.remindersEnabled,
                      title: const Text('Enable reminders'),
                      onChanged: (enabled) {
                        ref
                            .read(appControllerProvider.notifier)
                            .setRemindersEnabled(enabled);
                        if (!enabled) {
                          setState(() {
                            _lastReminderTestMessage = null;
                            _lastReminderTestSuccess = null;
                          });
                        }
                      },
                    ),
                    if (prefs.remindersEnabled)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Reminder time'),
                        subtitle: Text(_formatReminderTime(context, prefs)),
                        trailing: const Icon(Icons.schedule_outlined),
                        onTap: () => _pickReminderTime(prefs),
                      ),
                    if (prefs.remindersEnabled)
                      OutlinedButton.icon(
                        onPressed: _sendingTestReminder
                            ? null
                            : _sendTestReminder,
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: Text(
                          _sendingTestReminder
                              ? 'Sending test...'
                              : 'Send test notification',
                        ),
                      ),
                    if (prefs.remindersEnabled &&
                        _lastReminderTestMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _lastReminderTestMessage!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _lastReminderTestSuccess == true
                                    ? palette.accent
                                    : palette.warning,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _sectionHeader(context, 'Data Safety'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Backup vault',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vaultPath == null || vaultPath.isEmpty
                          ? 'Vault folder: Not configured'
                          : 'Vault folder: $vaultPath',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _vaultSyncStatusText(context, prefs),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: prefs.lastVaultSyncError == null
                            ? palette.textMuted
                            : palette.warning,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: _vaultBusy
                              ? null
                              : () => _configureBackupVault(prefs: prefs),
                          icon: const Icon(Icons.folder_open),
                          label: Text(
                            hasVaultPath ? 'Change folder' : 'Set folder',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _vaultBusy || !hasVaultPath
                              ? null
                              : _syncVaultNow,
                          icon: const Icon(Icons.sync),
                          label: const Text('Sync now'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(
                                    title: const Text('Backup & Restore'),
                                  ),
                                  body: const BackupRestoreScreen(),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.shield_outlined),
                          label: const Text('Backup & restore'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _sectionHeader(context, 'Advanced'),
            Card(
              child: Column(
                children: <Widget>[
                  ExpansionTile(
                    title: const Text('Vault key operations'),
                    subtitle: const Text(
                      'Passphrase changes and vault removal',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: <Widget>[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: _vaultBusy || !hasVaultPath
                                ? null
                                : _changeVaultPassphrase,
                            icon: const Icon(Icons.key_outlined),
                            label: const Text('Change passphrase'),
                          ),
                          TextButton.icon(
                            onPressed: _vaultBusy || !hasVaultPath
                                ? null
                                : _clearBackupVault,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Clear vault config'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('Permissions & reset'),
                    subtitle: const Text('Storage access and local reset'),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            openAppSettings();
                          },
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('Open system settings'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _confirmResetLocalData,
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset local app data'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionHeader(context, 'About & Support'),
            Card(
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('About'),
                    subtitle: Text(_appVersionLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showAboutDialog,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.code_outlined),
                    title: const Text('GitHub Repository'),
                    subtitle: const Text('anima-regem/glitch'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () {
                      _openExternalLink(_githubUrl);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.system_update_alt_outlined),
                    title: const Text('Check for updates'),
                    subtitle: const Text('Open latest releases page'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () {
                      _openExternalLink(
                        _updatesUrl,
                        successMessage: 'Opened latest release page.',
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.coffee_outlined),
                    title: const Text('Buy me a coffee'),
                    subtitle: const Text('buymeacoffee.com/vichukartha'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () {
                      _openExternalLink(_buyCoffeeUrl);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Buy me a coffee QR',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Scan to open the support page quickly.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () {
                            _openExternalLink(_buyCoffeeUrl);
                          },
                          child: Image.network(
                            _buyCoffeeQrUrl,
                            width: 220,
                            height: 220,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 220,
                                height: 220,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: palette.surfaceRaised,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: palette.surfaceStroke,
                                  ),
                                ),
                                child: Text(
                                  'Unable to load QR.\nTap to open link.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: palette.textMuted),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        _appName = info.appName.trim().isEmpty ? 'Glitch' : info.appName.trim();
        _packageName = info.packageName.trim();
        _appVersionLabel = 'Version ${info.version} (${info.buildNumber})';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _appName = 'Glitch';
        _appVersionLabel = 'Version unavailable';
      });
    }
  }

  Future<void> _openExternalLink(String url, {String? successMessage}) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) {
      return;
    }
    if (launched) {
      if (successMessage != null && successMessage.trim().isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not open link: $url')));
  }

  Future<void> _showAboutDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('About $_appName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(_appVersionLabel),
              if (_packageName.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text('Package: $_packageName'),
              ],
              const SizedBox(height: 10),
              const Text(
                'Glitch is a local-first focus tracker designed for calm single-task momentum.',
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _formatReminderTime(BuildContext context, AppPreferences prefs) {
    final time = TimeOfDay(
      hour: prefs.reminderHour,
      minute: prefs.reminderMinute,
    );
    return MaterialLocalizations.of(context).formatTimeOfDay(time);
  }

  String _vaultSyncStatusText(BuildContext context, AppPreferences prefs) {
    final hasVaultPath =
        prefs.backupVaultPath != null &&
        prefs.backupVaultPath!.trim().isNotEmpty;
    if (!hasVaultPath) {
      return 'Vault sync status will appear after setup.';
    }

    final error = prefs.lastVaultSyncError?.trim();
    if (error != null && error.isNotEmpty) {
      return 'Last vault sync failed: $error';
    }

    final successAt = prefs.lastVaultSyncAt;
    if (successAt == null) {
      return 'No successful vault sync recorded yet.';
    }

    final localizedDate = MaterialLocalizations.of(
      context,
    ).formatMediumDate(successAt.toLocal());
    final localizedTime = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(successAt.toLocal()));
    return 'Last vault sync: $localizedDate at $localizedTime';
  }

  Future<void> _pickReminderTime(AppPreferences prefs) async {
    final initial = TimeOfDay(
      hour: prefs.reminderHour,
      minute: prefs.reminderMinute,
    );
    final selected = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (selected == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    await ref
        .read(appControllerProvider.notifier)
        .setReminderTime(hour: selected.hour, minute: selected.minute);
  }

  Future<void> _sendTestReminder() async {
    setState(() => _sendingTestReminder = true);
    try {
      final success = await ref
          .read(appControllerProvider.notifier)
          .sendTestReminderNotification();
      if (!mounted) {
        return;
      }

      setState(() {
        _lastReminderTestSuccess = success;
        _lastReminderTestMessage = success
            ? 'Test sent. Lock your phone to verify background delivery if banners are hidden in-app.'
            : 'Notification permission is blocked. Enable it in system settings.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Test notification sent.' : 'Notification blocked.',
          ),
          action: success
              ? null
              : SnackBarAction(
                  label: 'Settings',
                  onPressed: () {
                    openAppSettings();
                  },
                ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingTestReminder = false);
      }
    }
  }

  Future<void> _configureBackupVault({required AppPreferences prefs}) async {
    final hasPermission = await _ensureStoragePermission();
    if (!hasPermission || !mounted) {
      return;
    }

    String? selectedDirectory;
    try {
      selectedDirectory = await FilePicker.platform.getDirectoryPath(
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

    if (selectedDirectory == null || !mounted) {
      return;
    }

    final passphrase = await showBackupPassphraseDialog(
      context: context,
      title: prefs.backupVaultPath == null
          ? 'Set vault passphrase'
          : 'Update vault passphrase',
      description:
          'This passphrase encrypts your vault snapshot and is required to restore on any device.',
      confirmPassphrase: true,
    );
    if (passphrase == null || !mounted) {
      return;
    }

    setState(() => _vaultBusy = true);
    try {
      await ref
          .read(appControllerProvider.notifier)
          .configureBackupVault(
            directoryPath: selectedDirectory,
            passphrase: passphrase,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup vault configured at $selectedDirectory'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to configure backup vault: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _vaultBusy = false);
      }
    }
  }

  Future<void> _syncVaultNow() async {
    final hasPermission = await _ensureStoragePermission();
    if (!hasPermission || !mounted) {
      return;
    }

    setState(() => _vaultBusy = true);
    try {
      final path = await ref
          .read(appControllerProvider.notifier)
          .syncBackupVaultNow();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Vault snapshot updated: $path')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Vault sync failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _vaultBusy = false);
      }
    }
  }

  Future<void> _changeVaultPassphrase() async {
    final hasPermission = await _ensureStoragePermission();
    if (!hasPermission || !mounted) {
      return;
    }

    final passphrase = await showBackupPassphraseDialog(
      context: context,
      title: 'Set new vault passphrase',
      description:
          'The latest vault snapshot will be re-encrypted with this passphrase.',
      confirmPassphrase: true,
    );
    if (passphrase == null || !mounted) {
      return;
    }

    setState(() => _vaultBusy = true);
    try {
      await ref
          .read(appControllerProvider.notifier)
          .updateBackupVaultPassphrase(passphrase: passphrase);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vault passphrase updated')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Passphrase update failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _vaultBusy = false);
      }
    }
  }

  Future<void> _clearBackupVault() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear backup vault?'),
          content: const Text(
            'This removes the configured folder and stored passphrase from this device.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    setState(() => _vaultBusy = true);
    try {
      await ref
          .read(appControllerProvider.notifier)
          .clearBackupVaultConfiguration();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup vault configuration cleared')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clear backup vault: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _vaultBusy = false);
      }
    }
  }

  Future<void> _confirmResetLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset local data?'),
          content: const Text(
            'This clears all local tasks, habits, projects, and app settings on this device.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await ref.read(appControllerProvider.notifier).resetLocalData();
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Local data reset complete')));
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
}
