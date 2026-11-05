import 'dart:async';
import 'dart:convert';

import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_tree_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestTreeStore store;
  late LocalTreeRepository repository;
  final pino = Tree(nombre: 'Pino', frecuenciaRiegoDias: 3);
  final roble = Tree(nombre: 'Roble', frecuenciaRiegoDias: 5);

  setUp(() {
    store = TestTreeStore();
    repository = LocalTreeRepository(store: store);
  });

  test('Distingue una clave ausente de una lista vacía guardada', () async {
    expect(await repository.load(), isNull);
    store.treeRecords = [];
    expect(await repository.load(), isEmpty);
  });

  test(
    'Conserva el formato SharedPreferences y recupera un guardado',
    () async {
      SharedPreferences.setMockInitialValues({});
      final realRepository = LocalTreeRepository();
      expect(await realRepository.load(), isNull);
      await realRepository.save([pino]);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getStringList('trees')!.single);
      expect(saved['trees'], [pino.toJson()]);
      expect(saved['events'], isEmpty);
      expect(
        (await LocalTreeRepository().load())!.single.toJson(),
        pino.toJson(),
      );
      await realRepository.save([]);
      expect(await LocalTreeRepository().load(), isEmpty);
    },
  );

  for (final invalid in [
    '{invalido',
    '[]',
    'null',
    '{"nombre": 12, "frecuenciaRiego": "3"}',
    '{"nombre": "Pino"}',
    '{"nombre":"Pino","frecuenciaRiego":"3","ultimoRiego":"fecha inválida"}',
  ]) {
    test('Rechaza registro inválido sin sobrescribir: $invalid', () async {
      final original = [jsonEncode(pino.toJson()), invalid];
      store.treeRecords = original;
      await expectLater(
        repository.load(),
        throwsA(isA<TreeStorageException>()),
      );
      await expectLater(
        repository.save([]),
        throwsA(isA<TreeStorageException>()),
      );
      expect(store.treeRecords, original);
      expect(store.writes, isEmpty);
    });
  }

  test('Maneja un tipo de preferencia incorrecto sin borrarlo', () async {
    SharedPreferences.setMockInitialValues({'trees': 'tipo incorrecto'});
    final realRepository = LocalTreeRepository();
    await expectLater(
      realRepository.load(),
      throwsA(isA<TreeStorageException>()),
    );
    expect(
      (await SharedPreferences.getInstance()).getString('trees'),
      'tipo incorrecto',
    );
  });

  test('Permite reintentar una lectura fallida', () async {
    store.readError = StateError('sin acceso');
    await expectLater(repository.load(), throwsA(isA<TreeStorageException>()));
    store.readError = null;
    store.treeRecords = [jsonEncode(pino.toJson())];
    expect((await repository.load())!.single.nombre, 'Pino');
    await repository.save([roble]);
    expect(jsonDecode(store.treeRecords!.single)['nombre'], 'Roble');
  });

  test('No guarda antes de completar una carga válida', () async {
    await expectLater(
      repository.save([pino]),
      throwsA(isA<TreeStorageException>()),
    );
    expect(store.writes, isEmpty);
  });

  test('Espera la carga pendiente antes de guardar', () async {
    store.readGate = Completer<void>();
    final load = repository.load();
    final save = repository.save([pino]);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, isEmpty);
    store.readGate!.complete();
    await load;
    await save;
    expect(store.writes, hasLength(1));
  });

  test('Serializa escrituras, copia la lista y ordena las lecturas', () async {
    await repository.load();
    store.writeGate = Completer<void>();
    final first = repository.save([pino]);
    final next = [roble];
    final second = repository.save(next);
    next.clear();
    final read = repository.load();
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, hasLength(1));
    expect(store.reads, 1);
    store.writeGate!.complete();
    await Future.wait([first, second]);
    expect((await read)!.single.nombre, 'Roble');
    expect(store.writes, hasLength(2));
    expect(jsonDecode(store.treeRecords!.single)['nombre'], 'Roble');
  });

  for (final throwsError in [false, true]) {
    test(
      'Informa fallo de escritura y permite reintentar: $throwsError',
      () async {
        store.treeRecords = [jsonEncode(pino.toJson())];
        await repository.load();
        store.writeResult = throwsError;
        store.writeError = throwsError ? StateError('sin espacio') : null;
        await expectLater(
          repository.save([roble]),
          throwsA(isA<TreeStorageException>()),
        );
        expect(jsonDecode(store.treeRecords!.single)['nombre'], 'Pino');
        store.writeResult = true;
        store.writeError = null;
        await repository.save([roble]);
        expect((await repository.load())!.single.nombre, 'Roble');
      },
    );
  }
  test(
    'Actualiza registros antiguos una sola vez y conserva los IDs al reabrir',
    () async {
      store.treeRecords = [
        jsonEncode({
          'nombre': 'Pino',
          'especie': 'Pinus',
          'altura': 2,
          'frecuenciaRiego': '3 días',
          'ultimoRiego': '2026-11-03T10:00:00.000Z',
        }),
      ];
      final first = (await repository.load())!.single;
      expect(store.writes, hasLength(1));
      final saved = jsonDecode(store.treeRecords!.single);
      expect(saved['id'], first.id);
      expect(saved['frecuenciaRiegoDias'], 3);
      expect(saved.containsKey('frecuenciaRiego'), isFalse);
      final reopened = (await LocalTreeRepository(store: store).load())!.single;
      expect(reopened.toJson(), first.toJson());
      expect(store.writes, hasLength(1));
    },
  );

  test(
    'Un fallo al actualizar formato conserva datos y permite reintentar',
    () async {
      final original = [
        jsonEncode({'nombre': 'Pino', 'frecuenciaRiego': '3 días'}),
      ];
      store.treeRecords = original;
      store.writeResult = false;
      await expectLater(
        repository.load(),
        throwsA(isA<TreeStorageException>()),
      );
      expect(store.treeRecords, original);
      await expectLater(
        repository.save([]),
        throwsA(isA<TreeStorageException>()),
      );
      store.writeResult = true;
      final first = (await repository.load())!.single;
      expect(
        (await LocalTreeRepository(store: store).load())!.single.id,
        first.id,
      );
    },
  );

  test('Valida todos los registros antes de actualizar el formato', () async {
    final original = [
      jsonEncode({'nombre': 'Pino', 'frecuenciaRiego': '3 días'}),
      jsonEncode({'nombre': 'Roble', 'frecuenciaRiego': '2.5 días'}),
    ];
    store.treeRecords = original;
    await expectLater(repository.load(), throwsA(isA<TreeStorageException>()));
    expect(store.treeRecords, original);
    expect(store.writes, isEmpty);
  });

  test(
    'Guarda ediciones de plantas homónimas sin cambiar sus identidades',
    () async {
      final first = Tree(
        nombre: 'Pino',
        frecuenciaRiegoDias: 3,
        ultimoRiego: DateTime.utc(2026),
      );
      final second = Tree(nombre: 'Pino', frecuenciaRiegoDias: 7);
      await repository.load();
      await repository.save([first, second]);
      final reopened = LocalTreeRepository(store: store);
      final plants = (await reopened.load())!;
      plants[0] = plants[0].copyWith(
        nombre: 'Pino editado',
        especie: null,
        altura: 1.5,
        frecuenciaRiegoDias: 4,
      );
      await reopened.save(plants);
      final saved = (await LocalTreeRepository(store: store).load())!;
      expect(saved[0].id, first.id);
      expect(saved[0].nombre, 'Pino editado');
      expect(saved[0].altura, 1.5);
      expect(saved[0].frecuenciaRiegoDias, 4);
      expect(saved[0].ultimoRiego, first.ultimoRiego);
      expect(saved[1].toJson(), second.toJson());
    },
  );

  test('Rechaza IDs duplicados en carga y guardado sin escribir', () async {
    store.treeRecords = [jsonEncode(pino.toJson()), jsonEncode(pino.toJson())];
    await expectLater(repository.load(), throwsA(isA<TreeStorageException>()));
    expect(store.writes, isEmpty);
    store.treeRecords = [];
    await repository.load();
    await expectLater(
      repository.save([pino, pino.copyWith(nombre: 'Otro')]),
      throwsA(isA<TreeStorageException>()),
    );
    expect(store.treeRecords, isEmpty);
    expect(store.writes, isEmpty);
  });
}
