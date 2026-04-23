import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/services.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    String timeZoneName = await FlutterTimezone.getLocalTimezone();
    
    // Fix for older generic Android/Emulator issues where it returns Calcutta
    if (timeZoneName == 'Asia/Calcutta') {
      timeZoneName = 'Asia/Kolkata';
    }
    
    try {
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap
      },
    );

    await createNotificationChannel();
  }

  Future<void> createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'med_reminders_v2', // Changed ID to ensure fresh settings
      'Medication Reminders',
      description: 'Critical notifications for your medicine schedule',
      importance: Importance.max,
      playSound: true,
      showBadge: true,
      enableVibration: true,
      enableLights: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<bool> requestPermission() async {
    final status = await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    return status ?? false;
  }

  Future<bool> isPermissionGranted() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await androidImplementation?.areNotificationsEnabled() ?? false;
  }

  Future<void> openSettings() async {
    await AppSettings.openAppSettings(type: AppSettingsType.notification);
  }

  Future<void> scheduleMedicationNotifications({
    required int medId,
    required String name,
    required String dosage,
    required String timeStr,
  }) async {
    if (timeStr == "DEBUG_TEST") {
      final now = DateTime.now().add(const Duration(seconds: 5));
      await _notificationsPlugin.zonedSchedule(
        9999,
        '🚀 Test Notification',
        'Your medication adherence engine is working perfectly!',
        tz.TZDateTime.from(now, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'med_reminders_v2',
            'Medication Reminders',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
      return;
    }

    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    final now = DateTime.now();
    DateTime scheduledDate = DateTime(now.year, now.month, now.day, hour, minute);
    
    // If time has passed today (more than 2 minutes ago), skip scheduling.
    // If it's within the last 2 minutes, schedule it immediately for now so it triggers.
    // If time has passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    // 1. Scheduled Reminder
    final int reminderId = medId * 100 + hour; // Unique ID
    await _notificationsPlugin.zonedSchedule(
      reminderId,
      '⏰ Time to take \$name',
      'Take your dose of \$dosage now.',
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'med_reminders_v2',
          'Medication Reminders',
          channelDescription: 'Reminders to take your medication',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );

    // 2. Missed Dose Alert (1 hour later)
    final int missedId = reminderId + 5000; // Offset for missed dose
    await _notificationsPlugin.zonedSchedule(
      missedId,
      '⚠️ You missed your \$name',
      'It has been 1 hour since your scheduled dose of \$dosage.',
      tz.TZDateTime.from(scheduledDate.add(const Duration(hours: 1)), tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'med_reminders_v2',
          'Medication Reminders',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelMissedDoseNotification(int medId, int hour) async {
    final int missedId = (medId * 100 + hour) + 5000;
    await _notificationsPlugin.cancel(missedId);
  }

  Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }

  void triggerVibration() {
    HapticFeedback.heavyImpact();
  }

  void playSound() {
    SystemSound.play(SystemSoundType.click);
  }
}
