import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/state/app_controller.dart';

class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  bool _busy = false;
  String? _latestExportPath;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Text(
          'Backup & Restore',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Exports are encrypted with an AES key stored on this device.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _exportBackup,
          icon: const Icon(Icons.file_upload_outlined),
          label: const Text('Export encrypted JSON'),
        ),
        if (_latestExportPath != null) ...<Widget>[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () {
                    SharePlus.instance.share(
                      ShareParams(
                        files: <XFile>[XFile(_latestExportPath!)],
                        text: 'Glitch encrypted backup',
                      ),
                    );
                  },
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share last backup'),
          ),
          const SizedBox(height: 6),
          Text(
            _latestExportPath!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 22),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _importBackup,
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Import backup (overwrite all data)'),
        ),
      ],
    );
  }

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final path = await ref
          .read(appControllerProvider.notifier)
          .exportBackup();
      if (!mounted) {
        return;
      }

      setState(() {
        _latestExportPath = path;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup created at $path')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backup failed')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _importBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );

    final filePath = picked?.files.single.path;
    if (filePath == null || !mounted) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Overwrite current data?'),
          content: const Text(
            'Importing a backup will replace all existing tasks, habits, and projects.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Overwrite'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(appControllerProvider.notifier)
          .importBackupFromPath(filePath);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup imported successfully')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Import failed. Invalid backup key/file.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
