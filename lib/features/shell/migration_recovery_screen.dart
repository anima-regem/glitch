import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../features/backup/passphrase_prompt.dart';
import '../../shared/state/app_controller.dart';

class MigrationRecoveryScreen extends ConsumerStatefulWidget {
  const MigrationRecoveryScreen({super.key, required this.failureReason});

  final String failureReason;

  @override
  ConsumerState<MigrationRecoveryScreen> createState() =>
      _MigrationRecoveryScreenState();
}

class _MigrationRecoveryScreenState
    extends ConsumerState<MigrationRecoveryScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Data migration needs recovery',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Migration failed. You can retry, export a protected raw backup, or reset local data.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: 8),
                Text(
                  'Reason: ${widget.failureReason}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.warning),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _retryMigration,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry migration'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _exportRawBackup,
                    icon: const Icon(Icons.ios_share_outlined),
                    label: const Text('Export raw backup'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _confirmReset,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Reset local data'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retryMigration() async {
    setState(() {
      _busy = true;
    });

    try {
      await ref.read(appControllerProvider.notifier).retryDataMigration();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Retry failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _exportRawBackup() async {
    final passphrase = await showBackupPassphraseDialog(
      context: context,
      title: 'Protect raw backup',
      description:
          'Set a passphrase to export a raw encrypted backup before reset.',
      confirmPassphrase: true,
    );

    if (passphrase == null || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      final path = await ref
          .read(appControllerProvider.notifier)
          .exportRawMigrationBackup(passphrase: passphrase);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup exported: $path')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset local data?'),
          content: const Text(
            'This clears all local tasks, habits, projects, and preferences on this device.',
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

    setState(() {
      _busy = true;
    });

    try {
      await ref.read(appControllerProvider.notifier).resetLocalData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local data reset complete')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reset failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }
}
