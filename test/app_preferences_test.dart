import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/core/models/app_preferences.dart';

void main() {
  test('defaults keep backup vault unset and reminders disabled', () {
    final prefs = AppPreferences.defaults();

    expect(prefs.backupVaultPath, isNull);
    expect(prefs.backupVaultPromptDismissed, isFalse);
    expect(prefs.backupPromptDeferrals, 0);
    expect(prefs.remindersEnabled, isFalse);
    expect(prefs.reminderHour, 20);
    expect(prefs.reminderMinute, 0);
    expect(prefs.lastVaultSyncAt, isNull);
    expect(prefs.lastVaultSyncError, isNull);
    expect(prefs.dataSchemaVersion, AppPreferences.currentSchemaVersion);
    expect(prefs.lastMigrationResult, isNull);
  });

  test('json round-trip preserves backup vault preferences', () {
    final source = AppPreferences(
      useDarkMode: true,
      highContrast: true,
      textScale: 1.15,
      darkThemeStyle: DarkThemeStyle.black,
      remindersEnabled: true,
      reminderHour: 9,
      reminderMinute: 30,
      backupPromptDeferrals: 1,
      backupVaultPath: '/tmp/glitch-vault',
      backupVaultPromptDismissed: true,
      lastVaultSyncAt: DateTime(2026, 2, 20, 8, 45),
      lastVaultSyncError: 'Example',
      dataSchemaVersion: 2,
      lastMigrationResult: 'ok:example',
    );

    final restored = AppPreferences.fromJson(source.toJson());
    expect(restored.backupVaultPath, '/tmp/glitch-vault');
    expect(restored.backupVaultPromptDismissed, isTrue);
    expect(restored.backupPromptDeferrals, 1);
    expect(restored.darkThemeStyle, DarkThemeStyle.black);
    expect(restored.remindersEnabled, isTrue);
    expect(restored.reminderHour, 9);
    expect(restored.reminderMinute, 30);
    expect(restored.lastVaultSyncAt, DateTime(2026, 2, 20, 8, 45));
    expect(restored.lastVaultSyncError, 'Example');
    expect(restored.dataSchemaVersion, 2);
    expect(restored.lastMigrationResult, 'ok:example');
  });
}
