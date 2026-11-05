import 'package:blueflora/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const device = MethodChannel('blueflora/device');
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (call) async {
          calls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'areNotificationsEnabled' => true,
            'requestNotificationsPermission' => false,
            'pendingNotificationRequests' => <Map<String, dynamic>>[],
            _ => null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          device,
          (call) async => 'America/Mexico_City',
        );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(device, null);
  });
  test(
    'Inicializar no solicita permisos; consulta zona real de Android',
    () async {
      final service = NotificationService();
      await service.initialize();
      await service.initialize();
      expect(calls.where((call) => call.method == 'initialize'), hasLength(1));
      expect(calls.any((call) => call.method.contains('Permission')), isFalse);
      expect((await service.localZone()).name, 'America/Mexico_City');
      expect(await service.hasPermission(), isTrue);
    },
  );
  test(
    'Permiso denegado se devuelve como false sin lanzar excepción',
    () async {
      expect(await NotificationService().requestPermission(), isFalse);
      expect(
        calls.where((call) => call.method == 'requestNotificationsPermission'),
        hasLength(1),
      );
    },
  );
  test(
    'Programa con ID estable, zona, icono y modo inexacto; permite cancelar',
    () async {
      final service = NotificationService();
      final zone = await service.localZone();
      final at = tz.TZDateTime.from(
        DateTime.now().add(const Duration(days: 3)),
        zone,
      );
      await service.schedule(
        id: 15,
        title: 'Riego',
        body: 'Aviso calendario',
        at: at,
        payload: 'plant-1',
      );
      final call = calls.singleWhere((call) => call.method == 'zonedSchedule');
      final args = call.arguments as Map;
      expect(args['id'], 15);
      expect(args['payload'], 'plant-1');
      expect(args['timeZoneName'], 'America/Mexico_City');
      expect(
        (args['platformSpecifics'] as Map)['scheduleMode'],
        'inexactAllowWhileIdle',
      );
      expect((args['platformSpecifics'] as Map)['icon'], 'ic_stat_leaf');
      expect(
        calls.any((call) => call.method == 'requestExactAlarmsPermission'),
        isFalse,
      );
      await service.cancel(15);
      expect(calls.where((call) => call.method == 'cancel'), hasLength(1));
      expect(await service.pending(), isEmpty);
    },
  );
  test('Un fallo de inicialización se puede reintentar', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (_) async => false);
    final service = NotificationService();
    await expectLater(service.initialize(), throwsStateError);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (_) async => true);
    await service.initialize();
  });
  test('Plataforma no Android informa que no está soportada', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await expectLater(
      NotificationService().initialize(),
      throwsUnsupportedError,
    );
  });
}
