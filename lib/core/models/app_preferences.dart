import 'package:flutter/foundation.dart';

enum DarkThemeStyle { amoled, black }

extension DarkThemeStyleLabel on DarkThemeStyle {
  String get label {
    switch (this) {
      case DarkThemeStyle.amoled:
        return 'AMOLED';
      case DarkThemeStyle.black:
        return 'Black';
    }
  }

  static DarkThemeStyle fromStorage(String? value) {
    return DarkThemeStyle.values.firstWhere(
      (item) => item.name == value,
      orElse: () => DarkThemeStyle.amoled,
    );
  }
}

@immutable
class AppPreferences {
  const AppPreferences({
    required this.useDarkMode,
    required this.highContrast,
    required this.textScale,
    required this.darkThemeStyle,
    required this.remindersEnabled,
    required this.reminderHour,
    required this.reminderMinute,
    required this.backupPromptDeferrals,
    required this.voiceTypingEnabled,
    required this.voiceTypingAllowNetworkFallback,
    this.backupVaultPath,
    this.backupVaultPromptDismissed = false,
    this.lastVaultSyncAt,
    this.lastVaultSyncError,
    this.dataSchemaVersion = currentSchemaVersion,
    this.lastMigrationResult,
  });

  static const int currentSchemaVersion = 2;

  factory AppPreferences.defaults() {
    return const AppPreferences(
      useDarkMode: true,
      highContrast: false,
      textScale: 1,
      darkThemeStyle: DarkThemeStyle.amoled,
      remindersEnabled: false,
      reminderHour: 20,
      reminderMinute: 0,
      backupPromptDeferrals: 0,
      voiceTypingEnabled: true,
      voiceTypingAllowNetworkFallback: false,
      backupVaultPath: null,
      backupVaultPromptDismissed: false,
      lastVaultSyncAt: null,
      lastVaultSyncError: null,
      dataSchemaVersion: currentSchemaVersion,
      lastMigrationResult: null,
    );
  }

  final bool useDarkMode;
  final bool highContrast;
  final double textScale;
  final DarkThemeStyle darkThemeStyle;
  final bool remindersEnabled;
  final int reminderHour;
  final int reminderMinute;
  final int backupPromptDeferrals;
  final bool voiceTypingEnabled;
  final bool voiceTypingAllowNetworkFallback;
  final String? backupVaultPath;
  final bool backupVaultPromptDismissed;
  final DateTime? lastVaultSyncAt;
  final String? lastVaultSyncError;
  final int dataSchemaVersion;
  final String? lastMigrationResult;

  AppPreferences copyWith({
    bool? useDarkMode,
    bool? highContrast,
    double? textScale,
    DarkThemeStyle? darkThemeStyle,
    bool? remindersEnabled,
    int? reminderHour,
    int? reminderMinute,
    int? backupPromptDeferrals,
    bool? voiceTypingEnabled,
    bool? voiceTypingAllowNetworkFallback,
    String? backupVaultPath,
    bool? backupVaultPromptDismissed,
    DateTime? lastVaultSyncAt,
    String? lastVaultSyncError,
    int? dataSchemaVersion,
    String? lastMigrationResult,
    bool clearBackupVaultPath = false,
    bool clearLastVaultSyncAt = false,
    bool clearLastVaultSyncError = false,
    bool clearLastMigrationResult = false,
  }) {
    return AppPreferences(
      useDarkMode: useDarkMode ?? this.useDarkMode,
      highContrast: highContrast ?? this.highContrast,
      textScale: textScale ?? this.textScale,
      darkThemeStyle: darkThemeStyle ?? this.darkThemeStyle,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      backupPromptDeferrals:
          backupPromptDeferrals ?? this.backupPromptDeferrals,
      voiceTypingEnabled: voiceTypingEnabled ?? this.voiceTypingEnabled,
      voiceTypingAllowNetworkFallback:
          voiceTypingAllowNetworkFallback ??
          this.voiceTypingAllowNetworkFallback,
      backupVaultPath: clearBackupVaultPath
          ? null
          : (backupVaultPath ?? this.backupVaultPath),
      backupVaultPromptDismissed:
          backupVaultPromptDismissed ?? this.backupVaultPromptDismissed,
      lastVaultSyncAt: clearLastVaultSyncAt
          ? null
          : (lastVaultSyncAt ?? this.lastVaultSyncAt),
      lastVaultSyncError: clearLastVaultSyncError
          ? null
          : (lastVaultSyncError ?? this.lastVaultSyncError),
      dataSchemaVersion:
          dataSchemaVersion ?? this.dataSchemaVersion.clamp(1, 9999).toInt(),
      lastMigrationResult: clearLastMigrationResult
          ? null
          : (lastMigrationResult ?? this.lastMigrationResult),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'useDarkMode': useDarkMode,
      'highContrast': highContrast,
      'textScale': textScale,
      'darkThemeStyle': darkThemeStyle.name,
      'remindersEnabled': remindersEnabled,
      'reminderHour': reminderHour,
      'reminderMinute': reminderMinute,
      'backupPromptDeferrals': backupPromptDeferrals,
      'voiceTypingEnabled': voiceTypingEnabled,
      'voiceTypingAllowNetworkFallback': voiceTypingAllowNetworkFallback,
      'backupVaultPath': backupVaultPath,
      'backupVaultPromptDismissed': backupVaultPromptDismissed,
      'lastVaultSyncAt': lastVaultSyncAt?.toIso8601String(),
      'lastVaultSyncError': lastVaultSyncError,
      'dataSchemaVersion': dataSchemaVersion,
      'lastMigrationResult': lastMigrationResult,
    };
  }

  factory AppPreferences.fromJson(Map<String, dynamic> json) {
    final path = (json['backupVaultPath'] as String?)?.trim();
    final rawHour = (json['reminderHour'] as num?)?.toInt() ?? 20;
    final rawMinute = (json['reminderMinute'] as num?)?.toInt() ?? 0;
    final rawVersion =
        (json['dataSchemaVersion'] as num?)?.toInt() ?? currentSchemaVersion;

    return AppPreferences(
      useDarkMode: json['useDarkMode'] as bool? ?? true,
      highContrast: json['highContrast'] as bool? ?? false,
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1,
      darkThemeStyle: DarkThemeStyleLabel.fromStorage(
        json['darkThemeStyle'] as String?,
      ),
      remindersEnabled: json['remindersEnabled'] as bool? ?? false,
      reminderHour: rawHour.clamp(0, 23).toInt(),
      reminderMinute: rawMinute.clamp(0, 59).toInt(),
      backupPromptDeferrals:
          ((json['backupPromptDeferrals'] as num?)?.toInt() ?? 0)
              .clamp(0, 365)
              .toInt(),
      voiceTypingEnabled: json['voiceTypingEnabled'] as bool? ?? true,
      voiceTypingAllowNetworkFallback:
          json['voiceTypingAllowNetworkFallback'] as bool? ?? false,
      backupVaultPath: (path == null || path.isEmpty) ? null : path,
      backupVaultPromptDismissed:
          json['backupVaultPromptDismissed'] as bool? ?? false,
      lastVaultSyncAt: DateTime.tryParse(
        json['lastVaultSyncAt'] as String? ?? '',
      ),
      lastVaultSyncError:
          (json['lastVaultSyncError'] as String?)?.trim().isEmpty == true
          ? null
          : json['lastVaultSyncError'] as String?,
      dataSchemaVersion: rawVersion.clamp(1, 9999).toInt(),
      lastMigrationResult:
          (json['lastMigrationResult'] as String?)?.trim().isEmpty == true
          ? null
          : json['lastMigrationResult'] as String?,
    );
  }
}
