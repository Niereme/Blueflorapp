import 'dart:async';
import 'dart:convert';

import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/domain/plant_snapshot.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/domain/watering_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_tree_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestTreeStore store;
  late LocalTreeRepository repository;
  late Tree tree;
  late WateringEvent event;
  setUp(() {
    tree = Tree(nombre: 'Pino', frecuenciaRiegoDias: 3);
    event = WateringEvent(
      plantId: tree.id,
      plantName: tree.nombre,
      occurredAt: DateTime.utc(2026, 11, 4, 18),
    );
    store = TestTreeStore()..records = [jsonEncode(tree.toJson())];
    repository = LocalTreeRepository(store: store);
  });

  test(
    'Una escritura guarda la fecha de la planta y el evento juntos',
    () async {
      await repository.loadSnapshot();
      await repository.save(
        [tree.copyWith(ultimoRiego: event.occurredAt)],
        events: [event],
      );
      expect(store.writes, hasLength(1));
      expect(store.records, hasLength(1));
      final raw = jsonDecode(store.records!.single);
      expect(raw['trees'][0]['ultimoRiego'], event.toJson()['occurredAt']);
      expect(raw['events'], [event.toJson()]);
      final reopened = (await LocalTreeRepository(
        store: store,
      ).loadSnapshot())!;
      expect(reopened.events.single.id, event.id);
      expect(reopened.trees.single.id, tree.id);
      expect(
        reopened.trees.single.ultimoRiego,
        reopened.events.single.occurredAt,
      );
    },
  );

  test(
    'SharedPreferences persiste y recupera ambas listas bajo una única clave',
    () async {
      SharedPreferences.setMockInitialValues({
        'trees': [jsonEncode(tree.toJson())],
      });
      final real = LocalTreeRepository();
      await real.loadSnapshot();
      await real.save(
        [tree.copyWith(ultimoRiego: event.occurredAt)],
        events: [event],
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'trees'});
      final snapshot = (await LocalTreeRepository().loadSnapshot())!;
      expect(snapshot.events.single.toJson(), event.toJson());
      expect(snapshot.trees.single.ultimoRiego, event.occurredAt);
    },
  );

  test('No inventa historial al leer plantas con fechas antiguas', () async {
    final old = tree.copyWith(ultimoRiego: DateTime.utc(2025));
    store.records = [jsonEncode(old.toJson())];
    final snapshot = (await repository.loadSnapshot())!;
    expect(snapshot.events, isEmpty);
    expect(snapshot.trees.single.toJson(), old.toJson());
    expect(store.writes, isEmpty);
  });

  for (final throwsError in [false, true]) {
    test(
      'Guardado fallido no deja media operación: excepción=$throwsError',
      () async {
        final original = List<String>.of(store.records!);
        await repository.loadSnapshot();
        store.writeResult = false;
        store.writeError = throwsError ? StateError('fallo') : null;
        await expectLater(
          repository.save(
            [tree.copyWith(ultimoRiego: event.occurredAt)],
            events: [event],
          ),
          throwsA(isA<TreeStorageException>()),
        );
        expect(store.records, original);
        final reopened = (await LocalTreeRepository(
          store: store,
        ).loadSnapshot())!;
        expect(reopened.events, isEmpty);
        expect(reopened.trees.single.ultimoRiego, isNull);
        store.writeResult = true;
        store.writeError = null;
        await repository.save(
          [tree.copyWith(ultimoRiego: event.occurredAt)],
          events: [event],
        );
        expect((await repository.loadSnapshot())!.events.single.id, event.id);
      },
    );
  }

  test('Editar y eliminar plantas preserva su historial', () async {
    await repository.loadSnapshot();
    await repository.save(
      [tree.copyWith(ultimoRiego: event.occurredAt)],
      events: [event],
    );
    await repository.save([
      tree.copyWith(nombre: 'Renombrado', ultimoRiego: event.occurredAt),
    ]);
    expect((await repository.loadSnapshot())!.events.single.plantName, 'Pino');
    await repository.save([]);
    final reopened = (await LocalTreeRepository(store: store).loadSnapshot())!;
    expect(reopened.trees, isEmpty);
    expect(reopened.events.single.plantId, tree.id);
  });

  test(
    'Copia las dos listas al encolar y conserva eventos de la escritura anterior',
    () async {
      await repository.loadSnapshot();
      store.writeGate = Completer<void>();
      final plants = [tree.copyWith(ultimoRiego: event.occurredAt)];
      final events = [event];
      final first = repository.save(plants, events: events);
      plants.clear();
      events.clear();
      final second = repository.save([
        tree.copyWith(nombre: 'Renombrado', ultimoRiego: event.occurredAt),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, hasLength(1));
      store.writeGate!.complete();
      await Future.wait([first, second]);
      final snapshot = (await repository.loadSnapshot())!;
      expect(snapshot.trees.single.nombre, 'Renombrado');
      expect(snapshot.events.single.id, event.id);
    },
  );

  for (final corrupt in [
    {'schemaVersion': 1, 'trees': [], 'events': 'mal'},
    {'schemaVersion': 99, 'trees': [], 'events': []},
    {
      'schemaVersion': 1,
      'trees': [],
      'events': [
        {'id': 'evento', 'type': 'desconocido'},
      ],
    },
  ]) {
    test(
      'Corrupción del historial bloquea escrituras sin descartar contenido: $corrupt',
      () async {
        final original = [jsonEncode(corrupt)];
        store.records = original;
        await expectLater(
          repository.loadSnapshot(),
          throwsA(isA<TreeStorageException>()),
        );
        await expectLater(
          repository.save([]),
          throwsA(isA<TreeStorageException>()),
        );
        expect(store.records, original);
        expect(store.writes, isEmpty);
      },
    );
  }

  test('Eventos duplicados se rechazan antes de escribir', () async {
    await repository.loadSnapshot();
    await expectLater(
      repository.save([tree], events: [event, event]),
      throwsA(isA<TreeStorageException>()),
    );
    expect(store.writes, isEmpty);
  });

  test('Una instantánea vacía no se interpreta como formato antiguo', () async {
    store.records = [jsonEncode(PlantSnapshot(trees: []).toJson())];
    final snapshot = (await repository.loadSnapshot())!;
    expect(snapshot.trees, isEmpty);
    expect(snapshot.events, isEmpty);
    expect(store.writes, isEmpty);
  });
}
