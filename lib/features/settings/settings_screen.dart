import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../features/archive/archive_screen.dart';
import '../../features/backup/backup_restore_screen.dart';
import '../../shared/state/app_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('Failed to load settings')),
      data: (data) {
        final palette = context.glitchPalette;
        final prefs = data.preferences;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            Text(
              'Interface',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: palette.surfaceStroke),
              ),
              value: prefs.useDarkMode,
              onChanged: (value) {
                ref.read(appControllerProvider.notifier).setDarkMode(value);
              },
              title: const Text('Dark mode (AMOLED default)'),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Dark style',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Switch between pure AMOLED black and standard black.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: DarkThemeStyle.values
                          .map((style) {
                            return ChoiceChip(
                              label: Text(style.label),
                              selected: prefs.darkThemeStyle == style,
                              onSelected: (_) {
                                ref
                                    .read(appControllerProvider.notifier)
                                    .setDarkThemeStyle(style);
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: palette.surfaceStroke),
              ),
              value: prefs.highContrast,
              onChanged: (value) {
                ref.read(appControllerProvider.notifier).setHighContrast(value);
              },
              title: const Text('High contrast'),
            ),
            const SizedBox(height: 12),
            Text('Text size', style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: prefs.textScale,
              min: 1,
              max: 1.35,
              divisions: 7,
              label: prefs.textScale.toStringAsFixed(2),
              onChanged: (value) {
                ref.read(appControllerProvider.notifier).setTextScale(value);
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Data',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                title: const Text('Backup & Restore'),
                subtitle: const Text('Export/import encrypted JSON backups'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Backup & Restore')),
                        body: const BackupRestoreScreen(),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                title: const Text('Archive'),
                subtitle: const Text('Review archived entries'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Archive')),
                        body: const ArchiveScreen(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
