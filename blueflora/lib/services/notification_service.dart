import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class PendingReminder {
  const PendingReminder(this.id, this.payload);
  final int id;
  final String? payload;
}

abstract class NotificationGateway {
  Future<void> initialize();
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<tz.Location> localZone();
  Future<List<PendingReminder>> pending();
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required String payload,
  });
  Future<void> cancel(int id);
}

/// Único adaptador Android. No pide permisos ni alarmas exactas al arrancar.
class NotificationService implements NotificationGateway {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  static const _device = MethodChannel('blueflora/device');
  static const channelId = 'riego_channel';

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Los recordatorios están disponibles en Android.');
    }
    tzdata.initializeTimeZones();
    final initialized = await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_leaf'),
      ),
    );
    if (initialized != true) {
      throw StateError('No se pudieron inicializar las notificaciones.');
    }
    _initialized = true;
  }

  AndroidFlutterLocalNotificationsPlugin get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()!;
  @override
  Future<bool> hasPermission() async {
    await initialize();
    return await _android.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    await initialize();
    return await _android.requestNotificationsPermission() ?? false;
  }

  @override
  Future<tz.Location> localZone() async {
    await initialize();
    final name = await _device.invokeMethod<String>('timeZone');
    if (name == null) throw StateError('No se pudo consultar la zona horaria.');
    return tz.getLocation(name);
  }

  @override
  Future<List<PendingReminder>> pending() async {
    await initialize();
    return (await _plugin.pendingNotificationRequests())
        .map((request) => PendingReminder(request.id, request.payload))
        .toList();
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required String payload,
  }) async {
    await initialize();
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      at,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Recordatorios de riego',
          channelDescription:
              'Recordatorios basados en las fechas de tus plantas',
          icon: 'ic_stat_leaf',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await initialize();
    await _plugin.cancel(id);
  }
}
