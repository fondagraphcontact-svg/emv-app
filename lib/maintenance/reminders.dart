import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'maintenance_entry.dart';

/// Rappels d'entretien. Seuls iOS et Android planifient de vraies
/// notifications ; ailleurs (web, desktop, tests) les rappels restent visibles
/// dans le carnet uniquement.
abstract class ReminderScheduler {
  static ReminderScheduler instance =
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)
          ? LocalReminderScheduler()
          : const NoopReminderScheduler();

  bool get supported;

  /// Demande l'autorisation si nécessaire ; false si refusée ou indisponible.
  Future<bool> requestPermission();

  /// (Re)planifie le rappel par date de [entry], ou l'annule s'il n'en a plus.
  Future<void> sync(MaintenanceEntry entry);

  Future<void> cancel(MaintenanceEntry entry);

  /// Notification immédiate, utilisée quand un rappel kilométrique est atteint.
  Future<void> notifyKmDue(MaintenanceEntry entry);
}

class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  bool get supported => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> sync(MaintenanceEntry entry) async {}

  @override
  Future<void> cancel(MaintenanceEntry entry) async {}

  @override
  Future<void> notifyKmDue(MaintenanceEntry entry) async {}
}

class LocalReminderScheduler implements ReminderScheduler {
  static const _channelId = 'maintenance';
  static const _reminderHour = 9;

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _init;

  @override
  bool get supported => true;

  Future<void> _ensureInit() => _init ??= () async {
        tzdata.initializeTimeZones();
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            // La permission est demandée explicitement à la création d'un rappel.
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
          ),
        );
      }();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Rappels d\'entretien',
      channelDescription: 'Échéances du carnet d\'entretien',
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<bool> requestPermission() async {
    await _ensureInit();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(
            alert: true, badge: true, sound: true) ??
        false;
  }

  @override
  Future<void> sync(MaintenanceEntry entry) async {
    await _ensureInit();
    await _plugin.cancel(id: entry.notificationId);
    final due = entry.reminderDate;
    if (due == null) return;
    final at = DateTime(due.year, due.month, due.day, _reminderHour);
    if (!at.isAfter(DateTime.now())) return;
    // Instant absolu exprimé en UTC : évite d'embarquer le fuseau de l'appareil.
    await _plugin.zonedSchedule(
      id: entry.notificationId,
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Entretien à prévoir',
      body: entry.title,
    );
  }

  @override
  Future<void> cancel(MaintenanceEntry entry) async {
    await _ensureInit();
    await _plugin.cancel(id: entry.notificationId);
  }

  @override
  Future<void> notifyKmDue(MaintenanceEntry entry) async {
    await _ensureInit();
    await _plugin.show(
      id: entry.notificationId,
      title: 'Échéance kilométrique atteinte',
      body: '${entry.title} · ${formatKm(entry.reminderKm ?? 0)}',
      notificationDetails: _details,
    );
  }
}
