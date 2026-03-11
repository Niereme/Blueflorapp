import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {

  static final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future init() async {

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings =
        InitializationSettings(android: androidSettings);

    await notificationsPlugin.initialize(settings);
  }

  static Future showNotification({
    required String title,
    required String body,
  }) async {

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'riego_channel',
      'Recordatorios de riego',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await notificationsPlugin.show(
      0,
      title,
      body,
      details,
    );
  }
}