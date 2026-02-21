import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

abstract class ReminderService {
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    required String title,
    required String body,
    Set<int>? weekdays,
    int? dayInterval,
  });

  Future<void> cancelReminder();

  Future<bool> showTestNotification({
    required String title,
    required String body,
  });
}

class NoopReminderService implements ReminderService {
  const NoopReminderService();

  @override
  Future<void> cancelReminder() async {}

  @override
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    required String title,
    required String body,
    Set<int>? weekdays,
    int? dayInterval,
  }) async {}

  @override
  Future<bool> showTestNotification({
    required String title,
    required String body,
  }) async {
    return false;
  }
}

class LocalReminderService implements ReminderService {
  LocalReminderService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const int _dailyNotificationId = 41001;
  static const int _testNotificationId = 41002;
  static const int _weekdayNotificationIdBase = 41100;
  static const String _channelId = 'glitch_focus_reminders';
  static const String _channelName = 'Focus reminders';
  static const String _channelDescription =
      'Gentle reminders to pick one task and start.';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    required String title,
    required String body,
    Set<int>? weekdays,
    int? dayInterval,
  }) async {
    await _ensureInitialized();
    final granted = await _ensureNotificationPermission();
    if (!granted) {
      await cancelReminder();
      return;
    }

    await cancelReminder();

    final normalizedHour = hour.clamp(0, 23);
    final normalizedMinute = minute.clamp(0, 59);
    final cadenceWeekdays = _resolveCadenceWeekdays(
      weekdays: weekdays,
      dayInterval: dayInterval,
    );

    if (cadenceWeekdays.isEmpty) {
      final scheduled = _nextScheduleTime(
        hour: normalizedHour,
        minute: normalizedMinute,
      );
      await _plugin.zonedSchedule(
        _dailyNotificationId,
        title,
        body,
        scheduled,
        _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return;
    }

    for (final weekday in cadenceWeekdays) {
      final scheduled = _nextScheduleForWeekday(
        weekday: weekday,
        hour: normalizedHour,
        minute: normalizedMinute,
      );

      await _plugin.zonedSchedule(
        _weekdayNotificationIdBase + weekday,
        title,
        body,
        scheduled,
        _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  @override
  Future<void> cancelReminder() async {
    await _ensureInitialized();
    await _plugin.cancel(_dailyNotificationId);
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
      await _plugin.cancel(_weekdayNotificationIdBase + weekday);
    }
  }

  @override
  Future<bool> showTestNotification({
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();
    final granted = await _ensureNotificationPermission();
    if (!granted) {
      return false;
    }

    await _plugin.show(_testNotificationId, title, body, _notificationDetails);
    return true;
  }

  NotificationDetails get _notificationDetails {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
    );
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }

    tz_data.initializeTimeZones();
    try {
      final timezoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      // Fall back to default timezone data when local lookup is unavailable.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    _initialized = true;
  }

  Future<bool> _ensureNotificationPermission() async {
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final macos = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      final iosGranted = await ios?.requestPermissions(
        alert: true,
        badge: false,
        sound: true,
      );
      final macosGranted = await macos?.requestPermissions(
        alert: true,
        badge: false,
        sound: true,
      );
      return iosGranted ?? macosGranted ?? true;
    }

    return true;
  }

  List<int> _resolveCadenceWeekdays({Set<int>? weekdays, int? dayInterval}) {
    final normalized =
        (weekdays ?? const <int>{})
            .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
            .toSet()
            .toList(growable: false)
          ..sort();
    if (normalized.isNotEmpty) {
      return normalized;
    }

    if (dayInterval == null || dayInterval <= 1) {
      return const <int>[];
    }

    final interval = dayInterval.clamp(2, 7);
    final derived = <int>{};
    var cursor = DateTime.monday;
    while (cursor <= DateTime.sunday) {
      derived.add(cursor);
      cursor += interval;
    }

    final list = derived.toList(growable: false)..sort();
    return list;
  }

  tz.TZDateTime _nextScheduleTime({required int hour, required int minute}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  tz.TZDateTime _nextScheduleForWeekday({
    required int weekday,
    required int hour,
    required int minute,
  }) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    var daysUntil = (weekday - scheduled.weekday) % 7;
    if (daysUntil == 0 && !scheduled.isAfter(now)) {
      daysUntil = 7;
    }

    return scheduled.add(Duration(days: daysUntil));
  }
}
