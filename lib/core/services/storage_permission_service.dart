import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

enum StoragePermissionOutcome { granted, denied, permanentlyDenied }

class StoragePermissionResult {
  const StoragePermissionResult({required this.outcome, required this.message});

  final StoragePermissionOutcome outcome;
  final String message;

  bool get granted => outcome == StoragePermissionOutcome.granted;

  bool get canOpenSettings =>
      outcome == StoragePermissionOutcome.permanentlyDenied;
}

class StoragePermissionService {
  const StoragePermissionService();

  Future<StoragePermissionResult>
  ensureStoragePermissionForFolderAccess() async {
    if (!Platform.isAndroid) {
      return const StoragePermissionResult(
        outcome: StoragePermissionOutcome.granted,
        message: 'Storage permission is available.',
      );
    }

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdk = androidInfo.version.sdkInt;

    if (sdk >= 30) {
      final status = await _requestPermission(Permission.manageExternalStorage);
      return _mapStatus(
        status,
        deniedMessage:
            'Storage permission is required to select and write to backup folders.',
      );
    }

    final status = await _requestPermission(Permission.storage);
    return _mapStatus(
      status,
      deniedMessage:
          'Storage permission is required to select and write to backup folders.',
    );
  }

  Future<PermissionStatus> _requestPermission(Permission permission) async {
    final currentStatus = await permission.status;
    if (currentStatus.isGranted) {
      return currentStatus;
    }
    return permission.request();
  }

  StoragePermissionResult _mapStatus(
    PermissionStatus status, {
    required String deniedMessage,
  }) {
    if (status.isGranted) {
      return const StoragePermissionResult(
        outcome: StoragePermissionOutcome.granted,
        message: 'Storage permission granted.',
      );
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      return StoragePermissionResult(
        outcome: StoragePermissionOutcome.permanentlyDenied,
        message:
            '$deniedMessage Open app settings to grant the permission manually.',
      );
    }

    return StoragePermissionResult(
      outcome: StoragePermissionOutcome.denied,
      message: deniedMessage,
    );
  }
}
