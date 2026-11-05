import 'dart:async';
import 'dart:convert';

import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/domain/plant_snapshot.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/domain/watering_event.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_tree_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestTreeStore store;
  late TreesController controller;
  late Tree tree;
  late DateTime now;
  setUp(() {
    now = DateTime(2026, 11, 4, 12);
    tree = Tree(nombre: 'Pino', frecuenciaRiegoDias: 3);
    store = TestTreeStore()..records = [jsonEncode(tree.toJson())];
    controller = TreesController(
      repository: LocalTreeRepository(store: store),
      clock: () => now,
      autoRefresh: false,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'Registrar un riego publica exactamente un evento y la misma fecha',
    () async {
      await controller.load();
      expect(controller.eventsFor(), isEmpty);
      await controller.water(tree.id);
      final event = controller.eventsFor().single;
      expect(event.plantId, tree.id);
      expect(event.type, WateringEventType.manualRegistration);
      expect(
        controller
            .plantById(tree.id)!
            .ultimoRiego!
            .isAtSameMomentAs(event.occurredAt),
        isTrue,
      );
      expect(store.writes, hasLength(1));
      await controller.load();
      expect(controller.eventsFor().single.toJson(), event.toJson());
    },
  );

  test(
    'Dos llamadas simultáneas no duplican el evento ni publican estados parciales',
    () async {
      await controller.load();
      final states = <(int, bool)>[];
      controller.addListener(
        () => states.add((
          controller.eventsFor().length,
          controller.plantById(tree.id)!.ultimoRiego != null,
        )),
      );
      store.writeGate = Completer<void>();
      final first = controller.water(tree.id);
      expect(await controller.water(tree.id), isFalse);
      expect(controller.eventsFor(), isEmpty);
      expect(controller.plantById(tree.id)!.ultimoRiego, isNull);
      store.writeGate!.complete();
      expect(await first, isTrue);
      expect(states, [(0, false), (1, true)]);
      expect(controller.eventsFor(), hasLength(1));
    },
  );

  for (final useButtonAgain in [false, true]) {
    test(
      'Un reintento conserva el ID y fecha originales: botón=$useButtonAgain',
      () async {
        await controller.load();
        store.writeResult = false;
        expect(await controller.water(tree.id), isFalse);
        final failed = jsonDecode(store.writes.single.single);
        expect(controller.eventsFor(), isEmpty);
        expect(controller.plantById(tree.id)!.ultimoRiego, isNull);
        now = now.add(const Duration(minutes: 10));
        store.writeResult = true;
        expect(
          await (useButtonAgain
              ? controller.water(tree.id)
              : controller.retrySave()),
          isTrue,
        );
        expect(controller.eventsFor(), hasLength(1));
        expect(controller.eventsFor().single.toJson(), failed['events'][0]);
        expect(
          controller.plantById(tree.id)!.ultimoRiego!.toUtc(),
          controller.eventsFor().single.occurredAt,
        );
        expect(await controller.retrySave(), isFalse);
      },
    );
  }

  test('Historial de plantas homónimas queda separado por ID', () async {
    final other = Tree(nombre: tree.nombre, frecuenciaRiegoDias: 3);
    store.records = [jsonEncode(tree.toJson()), jsonEncode(other.toJson())];
    await controller.load();
    await controller.water(tree.id);
    now = now.add(const Duration(minutes: 1));
    await controller.water(other.id);
    expect(controller.eventsFor(tree.id).single.plantId, tree.id);
    expect(controller.eventsFor(other.id).single.plantId, other.id);
    expect(controller.eventsFor(), hasLength(2));
  });

  test(
    'Renombrar y eliminar conserva eventos con nombre al registrar',
    () async {
      await controller.load();
      await controller.water(tree.id);
      final event = controller.eventsFor().single;
      await controller.edit(
        controller.plantById(tree.id)!.copyWith(nombre: 'Roble'),
      );
      expect(controller.eventsFor().single.plantName, 'Pino');
      expect(controller.plantById(event.plantId)!.nombre, 'Roble');
      await controller.delete(tree.id);
      expect(controller.plantById(tree.id), isNull);
      expect(controller.eventsFor().single.id, event.id);
      await controller.load();
      expect(controller.eventsFor().single.id, event.id);
    },
  );

  test(
    'Carga eventos desordenados y los devuelve de más reciente a más antiguo',
    () async {
      final older = WateringEvent(
        plantId: tree.id,
        plantName: tree.nombre,
        occurredAt: DateTime.utc(2026, 1, 1),
      );
      final newest = WateringEvent(
        plantId: tree.id,
        plantName: tree.nombre,
        occurredAt: DateTime.utc(2026, 11, 4),
      );
      final middle = WateringEvent(
        plantId: tree.id,
        plantName: tree.nombre,
        occurredAt: DateTime.utc(2026, 8, 1),
      );
      store.records = [
        jsonEncode(
          PlantSnapshot(
            trees: [tree],
            events: [older, newest, middle],
          ).toJson(),
        ),
      ];
      await controller.load();
      expect(controller.eventsFor().map((event) => event.id), [
        newest.id,
        middle.id,
        older.id,
      ]);
      expect(() => controller.eventsFor().clear(), throwsUnsupportedError);
    },
  );

  test(
    'Editar nunca altera el último riego ni crea eventos adicionales',
    () async {
      await controller.load();
      await controller.water(tree.id);
      final original = controller.plantById(tree.id)!;
      await controller.edit(
        original.copyWith(nombre: 'Editado', ultimoRiego: DateTime.utc(2020)),
      );
      expect(controller.plantById(tree.id)!.ultimoRiego, original.ultimoRiego);
      expect(controller.eventsFor(), hasLength(1));
    },
  );

  test('Cargar fecha anterior no crea eventos ficticios', () async {
    store.records = [
      jsonEncode(tree.copyWith(ultimoRiego: DateTime.utc(2020)).toJson()),
    ];
    await controller.load();
    expect(controller.eventsFor(), isEmpty);
    expect(controller.plantById(tree.id)!.ultimoRiego, DateTime.utc(2020));
  });

  test('Un fallo al eliminar conserva la planta y todo su historial', () async {
    await controller.load();
    await controller.water(tree.id);
    final event = controller.eventsFor().single;
    store.writeError = StateError('sin espacio');
    expect(await controller.delete(tree.id), isFalse);
    expect(controller.plantById(tree.id), isNotNull);
    expect(controller.eventsFor().single.id, event.id);
  });
  test(
    'Reintentar una escritura con respuesta perdida conserva un solo evento',
    () async {
      await controller.load();
      store.persistBeforeFailure = true;
      store.writeError = StateError('respuesta perdida tras escribir');
      expect(await controller.water(tree.id), isFalse);
      expect(controller.eventsFor(), isEmpty);
      final persisted = PlantSnapshot.fromJson(
        jsonDecode(store.records!.single),
      );
      expect(persisted.events, hasLength(1));
      expect(
        persisted.trees.single.ultimoRiego!.isAtSameMomentAs(
          persisted.events.single.occurredAt,
        ),
        isTrue,
      );
      store.writeError = null;
      now = now.add(const Duration(minutes: 1));
      expect(await controller.water(tree.id), isTrue);
      final saved = PlantSnapshot.fromJson(jsonDecode(store.records!.single));
      expect(saved.events, hasLength(1));
      expect(saved.events.single.id, persisted.events.single.id);
      expect(controller.eventsFor().single.id, persisted.events.single.id);
    },
  );
}
