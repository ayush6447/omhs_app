import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminders.dart';

/// Local notifications: the measurement reminder, trend alerts that arrive
/// while the app is in the background, and push messages received while the
/// app is open (the system shows them itself otherwise).
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _reminderId = 1;
  static const _alertId = 2;
  static const _messageId = 3;

  static const _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Measurement reminders',
      channelDescription: 'Reminds you to take a reading.',
    ),
    iOS: DarwinNotificationDetails(),
  );

  static const _alertDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'trend_alerts',
      'Reading alerts',
      channelDescription: 'High, rising or unreliable readings.',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static const _messageDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'messages',
      'Messages',
      channelDescription: 'News from the OMHS team, e.g. firmware updates.',
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Never throws: without notifications the rest of the app still works.
  Future<void> init() async {
    try {
      tz_data.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (e) {
      debugPrint('Time zone unknown ($e); reminders use UTC');
    }
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Asked for when the user turns reminders on, not at launch.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// Asks for permission (Android 13+, iOS). True when notifications can be
  /// shown.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }
    return false;
  }

  /// Replaces the scheduled reminder with [s] (or removes it). Called at
  /// launch too, so a time-zone change moves it.
  Future<void> applyReminder(ReminderSchedule s) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _reminderId);
      if (!s.enabled) return;
      final first = nextReminder(
        tz.TZDateTime.now(tz.local),
        s,
        (y, m, d, h, min) => tz.TZDateTime(tz.local, y, m, d, h, min),
      ) as tz.TZDateTime;
      await _plugin.zonedSchedule(
        id: _reminderId,
        scheduledDate: first,
        title: 'Time to measure',
        body: 'Take a reading to keep your cholesterol trend up to date.',
        notificationDetails: _reminderDetails,
        // Inexact needs no alarm permission; a few minutes late is fine.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: s.repeat == ReminderRepeat.daily
            ? DateTimeComponents.time
            : DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (e) {
      debugPrint('Scheduling the reminder failed: $e');
    }
  }

  Future<void> showAlert(String title, String body) =>
      _show(_alertId, title, body, _alertDetails);

  /// A push message that arrived while the app is open.
  Future<void> showMessage(String title, String body) =>
      _show(_messageId, title, body, _messageDetails);

  Future<void> _show(
      int id, String title, String body, NotificationDetails details) async {
    if (!_ready) return;
    try {
      await _plugin.show(
          id: id, title: title, body: body, notificationDetails: details);
    } catch (e) {
      debugPrint('Showing a notification failed: $e');
    }
  }
}
