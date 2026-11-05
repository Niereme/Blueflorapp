import 'dart:async';
import 'dart:convert';
import 'package:blueflora/application/reminders_controller.dart';
import 'package:blueflora/application/settings_controller.dart';
import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/data/settings_repository.dart';
import 'package:blueflora/data/reminder_registry.dart';
import 'package:blueflora/domain/app_settings.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../support/reminder_fakes.dart';
import '../support/test_tree_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);
  late TestTreeStore plantStore;
  late MemoryJsonStore prefs;
  late MemoryJsonStore registry;
  late FakeNotificationGateway gateway;
  late TreesController trees;
  late SettingsController settings;
  late RemindersController reminders;
  late DateTime now;
  late Tree plant;
  setUp(() async {
    now = DateTime.utc(2026, 11, 4, 8);
    plant = Tree(
      nombre: 'Pino',
      frecuenciaRiegoDias: 3,
      ultimoRiego: now.subtract(const Duration(days: 2)),
    );
    plantStore = TestTreeStore()..records = [jsonEncode(plant.toJson())];
    prefs = MemoryJsonStore()
      ..value = jsonEncode(const AppSettings(remindersEnabled: true).toJson());
    registry = MemoryJsonStore();
    gateway = FakeNotificationGateway();
    trees = TreesController(
      repository: LocalTreeRepository(store: plantStore),
      clock: () => now,
      autoRefresh: false,
    );
    settings = SettingsController(repository: SettingsRepository(store: prefs));
    await trees.load();
    await settings.load();
    reminders = RemindersController(
      trees: trees,
      settings: settings,
      gateway: gateway,
      registry: ReminderRegistry(store: registry),
      clock: () => now,
    );
  });
  tearDown(() {
    reminders.dispose();
    settings.dispose();
    trees.dispose();
  });

  test(
    'Programa solo plantas con fecha válida sin solicitar permisos al arrancar',
    () async {
      await trees.add(Tree(nombre: 'Sin fecha', frecuenciaRiegoDias: 1));
      await reminders.sync();
      expect(gateway.jobs, hasLength(1));
      expect(gateway.requests, 0);
      expect(
        gateway.scheduled.single.at,
        tz.TZDateTime(tz.UTC, 2026, 11, 5, 9),
      );
      expect(gateway.scheduled.single.body, contains('calendario'));
    },
  );
  test('Reconciliar repetidamente no duplica pendientes', () async {
    await reminders.sync();
    final id = gateway.jobs.keys.single;
    await reminders.sync(force: true);
    await reminders.sync(force: true);
    expect(gateway.jobs.keys, [id]);
    expect(gateway.scheduled, hasLength(1));
  });
  test('Regar reprogama con el mismo ID y conserva el evento real', () async {
    await reminders.sync();
    final first = gateway.scheduled.single;
    await trees.water(plant.id);
    await reminders.sync();
    expect(gateway.jobs, hasLength(1));
    expect(gateway.scheduled.last.id, first.id);
    expect(gateway.scheduled.last.at.isAfter(first.at), isTrue);
    expect(trees.eventsFor(), hasLength(1));
  });
  test(
    'Editar nombre y frecuencia actualiza texto y fecha del mismo ID',
    () async {
      await reminders.sync();
      final id = gateway.jobs.keys.single;
      await trees.edit(plant.copyWith(nombre: 'Roble', frecuenciaRiegoDias: 5));
      await reminders.sync();
      expect(gateway.jobs.keys, [id]);
      expect(gateway.jobs[id]!.body, contains('Roble'));
      expect(gateway.jobs[id]!.at.day, 7);
    },
  );
  test('Agregar otra planta no modifica el ID de la primera', () async {
    await reminders.sync();
    final id = gateway.jobs.keys.single;
    await trees.add(
      Tree(nombre: plant.nombre, frecuenciaRiegoDias: 1, ultimoRiego: now),
    );
    await reminders.sync();
    expect(gateway.jobs, hasLength(2));
    expect(gateway.jobs.containsKey(id), isTrue);
    expect(gateway.scheduled, hasLength(2));
  });
  test('Eliminar cancela la alarma de la planta', () async {
    await reminders.sync();
    final id = gateway.jobs.keys.single;
    await trees.delete(plant.id);
    await reminders.sync();
    expect(gateway.jobs, isEmpty);
    expect(gateway.cancelled, contains(id));
  });
  test('Cambiar hora reprogama; cambiar solo tema no toca alarmas', () async {
    await reminders.sync();
    final id = gateway.jobs.keys.single;
    await settings.save(settings.value.copyWith(hour: 18, minute: 45));
    await reminders.sync();
    expect(gateway.jobs[id]!.at.hour, 18);
    expect(gateway.jobs[id]!.at.minute, 45);
    final count = gateway.scheduled.length;
    await settings.save(settings.value.copyWith(theme: AppTheme.dark));
    await reminders.sync();
    expect(gateway.scheduled.length, count);
  });
  test('Desactivar cancela pendientes y no pide permiso', () async {
    await reminders.sync();
    expect(await reminders.setEnabled(false), isTrue);
    expect(gateway.jobs, isEmpty);
    expect(settings.value.remindersEnabled, isFalse);
    expect(gateway.requests, 0);
    await reminders.sync(force: true);
    expect(gateway.jobs, isEmpty);
  });
  test('Rechazar permiso deja la preferencia desactivada y no falla', () async {
    await reminders.setEnabled(false);
    gateway.requestResult = false;
    expect(await reminders.setEnabled(true), isFalse);
    expect(settings.value.remindersEnabled, isFalse);
    expect(gateway.jobs, isEmpty);
    expect(reminders.permissionDenied, isTrue);
    expect(reminders.error, contains('rechazado'));
    expect(gateway.requests, 1);
  });
  test(
    'Permiso revocado cancela pendientes sin solicitarlo automáticamente',
    () async {
      await reminders.sync();
      gateway.granted = false;
      reminders.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await reminders.sync();
      expect(gateway.jobs, isEmpty);
      expect(reminders.permissionDenied, isTrue);
      expect(gateway.requests, 0);
    },
  );
  test(
    'Error del plugin no revierte riegos confirmados y permite reintentar',
    () async {
      await reminders.sync();
      gateway.scheduleError = StateError('fallo Android');
      await trees.water(plant.id);
      await reminders.sync();
      expect(trees.eventsFor(), hasLength(1));
      expect(trees.plantById(plant.id)!.ultimoRiego, now);
      expect(reminders.error, isNotNull);
      gateway.scheduleError = null;
      await reminders.sync(force: true);
      expect(reminders.error, isNull);
      expect(gateway.jobs, hasLength(1));
    },
  );
  test('Error al cancelar se informa y se puede reintentar', () async {
    await reminders.sync();
    gateway.cancelError = StateError('fallo');
    await reminders.setEnabled(false);
    expect(reminders.error, isNotNull);
    expect(gateway.jobs, hasLength(1));
    gateway.cancelError = null;
    await reminders.sync(force: true);
    expect(gateway.jobs, isEmpty);
    expect(reminders.error, isNull);
  });
  test('Registro de IDs dañado no impide cancelar al desactivar', () async {
    await reminders.sync();
    registry.value = '{mal';
    await reminders.setEnabled(false);
    expect(gateway.jobs, isEmpty);
    expect(reminders.error, isNotNull);
    expect(registry.value, '{mal');
  });
  test(
    'Fallo al persistir ID impide programar una alarma sin identidad estable',
    () async {
      registry.writeResult = false;
      await reminders.sync();
      expect(gateway.jobs, isEmpty);
      expect(reminders.error, isNotNull);
      registry.writeResult = true;
      await reminders.sync(force: true);
      expect(gateway.jobs, hasLength(1));
    },
  );
  test('Un guardado fallido de plantas no cambia el recordatorio', () async {
    await reminders.sync();
    final original = gateway.jobs.values.single;
    plantStore.writeResult = false;
    await trees.water(plant.id);
    await reminders.sync();
    expect(gateway.jobs.values.single.payload, original.payload);
    expect(gateway.scheduled, hasLength(1));
  });
  test('Después de reiniciar conserva IDs y no duplica alarmas', () async {
    await reminders.sync();
    final id = gateway.jobs.keys.single;
    final other = RemindersController(
      trees: trees,
      settings: settings,
      gateway: gateway,
      registry: ReminderRegistry(store: registry),
      clock: () => now,
    );
    try {
      await other.sync();
      expect(gateway.jobs.keys, [id]);
      expect(gateway.scheduled, hasLength(1));
    } finally {
      other.dispose();
    }
  });
  test(
    'Un vencido ya intentado no se repite al reabrir ni en días siguientes',
    () async {
      await trees.edit(plant.copyWith(frecuenciaRiegoDias: 1));
      await reminders.sync();
      final id = gateway.jobs.keys.single;
      now = DateTime.utc(2026, 11, 4, 10);
      gateway.jobs.remove(id); // Android ya consumió la alarma.
      await reminders.sync(force: true);
      now = now.add(const Duration(days: 3));
      await reminders.sync(force: true);
      expect(gateway.jobs, isEmpty);
      expect(gateway.scheduled, hasLength(1));
    },
  );
  test(
    'Desactivar antes de la entrega permite reactivar después sin perder ese ciclo',
    () async {
      await reminders.sync();
      await reminders.setEnabled(false);
      now = now.add(const Duration(days: 3));
      await reminders.setEnabled(true);
      expect(gateway.jobs, hasLength(1));
      expect(gateway.jobs.values.single.at.isAfter(now), isTrue);
    },
  );
  test(
    'Al reanudar tras cambiar zona horaria actualiza la hora local',
    () async {
      await reminders.sync();
      final id = gateway.jobs.keys.single;
      gateway.zone = tz.getLocation('America/Mexico_City');
      reminders.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await reminders.sync();
      expect(gateway.jobs[id]!.at.location.name, 'America/Mexico_City');
      expect(gateway.jobs[id]!.at.hour, 9);
    },
  );
  test(
    'Cambios mientras Android espera se reconcilian en orden sin alarmas obsoletas',
    () async {
      gateway.scheduleGate = Completer<void>();
      final sync = reminders.sync();
      await Future<void>.delayed(Duration.zero);
      await trees.delete(plant.id);
      gateway.scheduleGate!.complete();
      await sync;
      await reminders.sync();
      expect(gateway.jobs, isEmpty);
    },
  );
}
