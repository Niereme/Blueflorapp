import 'dart:convert';
import 'dart:io';

import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/data/storage/file_migration_backup.dart';
import 'package:blueflora/data/storage/migration_source.dart';
import 'package:blueflora/data/storage/sqlite_tree_repository.dart';
import 'package:blueflora/data/storage/storage_platform_policy.dart';
import 'package:blueflora/data/storage/tree_repository_factory_stub.dart'
    as web;
import 'package:blueflora/domain/plant_snapshot.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/domain/watering_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_tree_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late TestTreeStore source;
  late FileMigrationBackup backups;
  late SqliteTreeRepository repo;
  final opened = <Database>[];
  final tree = Tree(
    id: '98313170-71b1-4b49-9d5a-873898c66f38',
    nombre: 'Árbol 🌿',
    especie: 'Especie libre',
    altura: 1.25,
    frecuenciaRiegoDias: 3,
    ultimoRiego: DateTime.utc(2026, 11, 1, 12),
  );
  final event = WateringEvent(
    plantId: tree.id,
    plantName: tree.nombre,
    occurredAt: DateTime.utc(2026, 11, 1, 12),
  );
  final orphan = WateringEvent(
    plantId: 'planta-eliminada',
    plantName: 'Nombre anterior',
    occurredAt: DateTime.utc(2025, 6, 1),
  );

  Future<Database> open() async {
    final db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/plants.sqlite',
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onConfigure: SqliteTreeRepository.configure,
        onCreate: SqliteTreeRepository.createSchema,
      ),
    );
    opened.add(db);
    return db;
  }

  SqliteTreeRepository repository({StorageCheckpoint? checkpoint}) =>
      SqliteTreeRepository(
        openDatabase: open,
        source: source,
        backups: backups,
        checkpoint: checkpoint,
      );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('blueflora-sqlite-test-');
    source = TestTreeStore();
    backups = FileMigrationBackup(Directory('${directory.path}/backups'));
    repo = repository();
  });
  tearDown(() async {
    for (final db in opened) {
      if (db.isOpen) await db.close();
    }
    opened.clear();
    await directory.delete(recursive: true);
  });

  void seed({List<WateringEvent>? events}) {
    source.records = [
      jsonEncode(
        PlantSnapshot(
          trees: [tree],
          events: events ?? [event, orphan],
        ).toJson(),
      ),
    ];
  }

  test('Migra snapshot íntegro, conserva origen y eventos huérfanos', () async {
    seed();
    final original = List.of(source.records!);
    final snapshot = (await repo.loadSnapshot())!;
    expect(snapshot.trees.single.toJson(), tree.toJson());
    expect(snapshot.events.map((e) => e.toJson()), [
      event.toJson(),
      orphan.toJson(),
    ]);
    expect(source.records, original);
    expect(source.writes, isEmpty);
    final db = opened.single;
    expect(await db.query('plant_references'), hasLength(2));
    expect(await db.query('plants'), hasLength(1));
    final backup = (await db.query('recovery_backups')).single;
    expect(
      jsonDecode(await backups.read(backup['hash'] as String))['records'],
      original,
    );
  });

  test('Migración repetida no duplica filas ni respaldos', () async {
    seed();
    await repo.loadSnapshot();
    await repo.loadSnapshot();
    await repo.close();
    final next = repository();
    expect((await next.loadSnapshot())!.events, hasLength(2));
    expect(await opened.last.query('migration_runs'), hasLength(1));
    expect(await backups.directory.list().toList(), hasLength(1));
  });

  test(
    'Ausente y vacío son distintos, sin inventar plantas ni eventos',
    () async {
      expect(await repo.loadSnapshot(), isNull);
      await repo.save([]);
      expect((await repo.loadSnapshot())!.trees, isEmpty);
      expect(source.records, isNull);
    },
  );

  test('Lista vacía antigua se conserva vacía tras reiniciar', () async {
    source.records = [];
    expect((await repo.loadSnapshot())!.trees, isEmpty);
    expect((await repository().loadSnapshot())!.trees, isEmpty);
  });

  for (final stage in [
    'captured',
    'mapped',
    'plants_written',
    'staged',
    'verified',
    'activated',
  ]) {
    test('Interrupción en $stage se recupera sin duplicados', () async {
      source.records = [
        jsonEncode({
          'nombre': 'Legado',
          'frecuenciaRiego': '3 días',
          'ultimoRiego': null,
        }),
      ];
      var interrupted = false;
      final failing = repository(
        checkpoint: (name) async {
          if (name == stage && !interrupted) {
            interrupted = true;
            throw StateError('interrupción simulada');
          }
        },
      );
      final original = List.of(source.records!);
      if (stage == 'captured' || stage == 'activated') {
        await expectLater(
          failing.loadSnapshot(),
          throwsA(isA<TreeStorageException>()),
        );
      } else {
        expect((await failing.loadSnapshot())!.trees, hasLength(1));
        expect(failing.writable, isFalse);
        expect(failing.storageNotice, contains('solo lectura'));
        await expectLater(
          failing.save([]),
          throwsA(isA<TreeStorageException>()),
        );
      }
      final runs = await opened.last.query('migration_runs');
      final mappings = jsonDecode(runs.single['assigned_ids'] as String) as Map;
      await failing.close();
      final snapshot = (await repository().loadSnapshot())!;
      expect(snapshot.trees, hasLength(1));
      if (mappings.isNotEmpty) expect(snapshot.trees.single.id, mappings['0']);
      expect(snapshot.events, isEmpty);
      expect(source.records, original);
      expect(source.writes, isEmpty);
    });
  }

  test(
    'Persisten edición, riego y eliminación, con historia conservada',
    () async {
      seed(events: []);
      await repo.loadSnapshot();
      final edited = tree.copyWith(
        nombre: 'Nombre nuevo',
        especie: null,
        altura: null,
      );
      await repo.save([edited], events: [event]);
      await repo.close();
      final next = repository();
      final snapshot = (await next.loadSnapshot())!;
      expect(snapshot.trees.single.toJson(), edited.toJson());
      expect(snapshot.events.single.toJson(), event.toJson());
      await next.save([]);
      final deleted = (await repository().loadSnapshot())!;
      expect(deleted.trees, isEmpty);
      expect(deleted.events.single.plantId, tree.id);
      expect((await opened.last.query('plants')).single['deleted'], 1);
    },
  );

  test(
    'Fallo anterior a activación permite consultar origen y reintentar sin editarlo',
    () async {
      seed();
      var fail = true;
      final failing = repository(
        checkpoint: (name) async {
          if (name == 'verified' && fail) {
            throw StateError('fallo de confirmación');
          }
        },
      );
      final controller = TreesController(
        repository: failing,
        autoRefresh: false,
      );
      addTearDown(controller.dispose);
      expect(await controller.load(), isTrue);
      expect(controller.storageReadOnly, isTrue);
      expect(controller.canModify, isFalse);
      expect(controller.trees.single.toJson(), tree.toJson());
      expect(controller.eventsFor(), hasLength(2));
      expect(await controller.delete(tree.id), isFalse);
      expect(source.writes, isEmpty);
      fail = false;
      expect(await controller.load(), isTrue);
      expect(controller.storageReadOnly, isFalse);
      expect(controller.canModify, isTrue);
    },
  );

  test('Dos nombres iguales conservan UUID y riegos independientes', () async {
    source.records = [];
    await repo.loadSnapshot();
    final second = Tree(nombre: tree.nombre, frecuenciaRiegoDias: 2);
    await repo.save([tree, second], events: [event]);
    final snapshot = (await repository().loadSnapshot())!;
    expect(snapshot.trees.map((t) => t.id), [tree.id, second.id]);
    expect(snapshot.events.single.plantId, tree.id);
  });

  for (final stage in ['plants_written', 'before_save_commit']) {
    test(
      'Fallo en $stage revierte planta e historial juntos; reintento único',
      () async {
        seed(events: []);
        var fail = false;
        final failing = repository(
          checkpoint: (name) async {
            if (fail && name == stage) throw StateError('fallo de escritura');
          },
        );
        await failing.loadSnapshot();
        final watered = tree.copyWith(ultimoRiego: DateTime.utc(2026, 11, 6));
        fail = true;
        await expectLater(
          failing.save([watered], events: [event]),
          throwsA(isA<TreeStorageException>()),
        );
        final saved = (await repository().loadSnapshot())!;
        expect(saved.trees.single.toJson(), tree.toJson());
        expect(saved.events, isEmpty);
        fail = false;
        await failing.save([watered], events: [event]);
        await failing.save([watered], events: [event]);
        final finalState = (await repository().loadSnapshot())!;
        expect(finalState.events, hasLength(1));
        expect(finalState.trees.single.ultimoRiego, watered.ultimoRiego);
      },
    );
  }

  test('Rechaza escritor obsoleto sin sobrescribir cambios', () async {
    seed();
    final second = repository();
    await repo.loadSnapshot();
    await second.loadSnapshot();
    await repo.save([tree.copyWith(nombre: 'Confirmado')]);
    await expectLater(
      second.save([tree]),
      throwsA(isA<TreeStorageException>()),
    );
    expect((await second.loadSnapshot())!.trees.single.nombre, 'Confirmado');
  });

  test('No lee preferencias obsoletas después de activación', () async {
    seed();
    await repo.loadSnapshot();
    await repo.save([tree.copyWith(nombre: 'SQLite reciente')]);
    source.readError = StateError('preferencias no disponibles');
    expect(
      (await repository().loadSnapshot())!.trees.single.nombre,
      'SQLite reciente',
    );
  });

  test('Corrupción de base activa no vuelve a las preferencias', () async {
    seed();
    await repo.loadSnapshot();
    final reads = source.reads;
    await opened.last.execute('DROP TABLE plants');
    await expectLater(
      repository().loadSnapshot(),
      throwsA(isA<TreeStorageException>()),
    );
    expect(source.reads, reads);
  });

  test('No permite descartar ni modificar eventos históricos', () async {
    seed();
    await repo.loadSnapshot();
    await expectLater(
      repo.save([tree], events: []),
      throwsA(isA<TreeStorageException>()),
    );
    final changed = WateringEvent(
      id: event.id,
      plantId: tree.id,
      plantName: 'Otro',
      occurredAt: event.occurredAt,
    );
    await expectLater(
      repo.save([tree], events: [changed, orphan]),
      throwsA(isA<TreeStorageException>()),
    );
    expect((await repo.loadSnapshot())!.events.first.toJson(), event.toJson());
  });

  test(
    'Fechas locales se conservan sin imponer UTC; diagnóstico explícito',
    () async {
      final local = tree.toJson()
        ..['ultimoRiego'] = '2026-10-24T12:35:46.123456';
      source.records = [jsonEncode(local)];
      final snapshot = (await repo.loadSnapshot())!;
      expect(snapshot.trees.single.ultimoRiego!.isUtc, isFalse);
      expect(
        snapshot.trees.single.toJson()['ultimoRiego'],
        local['ultimoRiego'],
      );
      expect(repo.storageNotice, isNotNull);
      expect(
        (await opened.last.query('plants')).single['date_kind'],
        'local_unzoned',
      );
    },
  );

  test(
    'ID legado y textos extensos se conservan sin renombrar ni truncar',
    () async {
      final raw = tree.toJson()
        ..['id'] = 'ID antiguo'
        ..['nombre'] = List.filled(600, 'ñ').join();
      source.records = [jsonEncode(raw)];
      final snapshot = (await repo.loadSnapshot())!;
      expect(snapshot.trees.single.id, 'ID antiguo');
      expect(snapshot.trees.single.nombre, raw['nombre']);
      expect(repo.storageNotice, isNotNull);
    },
  );

  for (final invalid in [
    '{json roto',
    jsonEncode({'schemaVersion': 99, 'trees': [], 'events': []}),
    jsonEncode({...tree.toJson(), 'frecuenciaRiegoDias': 2.5}),
    jsonEncode({...tree.toJson(), 'nombre': '  nombre  '}),
    jsonEncode({...tree.toJson(), 'ultimoRiego': '2026-02-31T12:00:00'}),
    jsonEncode({...tree.toJson(), 'campoDesconocido': true}),
    jsonEncode({'nombre': 'Antiguo', 'frecuenciaRiego': '1 semana'}),
  ]) {
    test('Incompatible no activa SQLite ni toca origen: $invalid', () async {
      source.records = [invalid];
      await expectLater(
        repo.loadSnapshot(),
        throwsA(isA<TreeStorageException>()),
      );
      expect((await opened.last.query('storage_state')).single['active'], 0);
      expect(
        (await opened.last.query('migration_runs')).single['state'],
        'blocked',
      );
      expect(source.records, [invalid]);
      expect(source.writes, isEmpty);
      await expectLater(repo.save([]), throwsA(isA<TreeStorageException>()));
    });
  }

  test(
    'Eventos sin zona se bloquean, no se convierten al huso actual',
    () async {
      final rawEvent = event.toJson()..['occurredAt'] = '2026-10-24T01:30:00';
      source.records = [
        jsonEncode({
          'schemaVersion': 1,
          'trees': [tree.toJson()],
          'events': [rawEvent],
        }),
      ];
      await expectLater(
        repo.loadSnapshot(),
        throwsA(isA<TreeStorageException>()),
      );
      expect(source.writes, isEmpty);
    },
  );

  test('UUID duplicados bloquean sin perder registros', () async {
    source.records = [jsonEncode(tree.toJson()), jsonEncode(tree.toJson())];
    await expectLater(
      repo.loadSnapshot(),
      throwsA(isA<TreeStorageException>()),
    );
    expect(source.records, hasLength(2));
    expect(await opened.last.query('plants'), isEmpty);
  });

  test('Respaldo corrupto bloquea antes de importar', () async {
    seed();
    var fail = true;
    final failing = repository(
      checkpoint: (name) async {
        if (name == 'captured' && fail) throw StateError('interrupción');
      },
    );
    await expectLater(
      failing.loadSnapshot(),
      throwsA(isA<TreeStorageException>()),
    );
    final file = (await backups.directory.list().toList()).single as File;
    await file.writeAsString('corrupto', flush: true);
    fail = false;
    await expectLater(
      failing.loadSnapshot(),
      throwsA(isA<TreeStorageException>()),
    );
    expect((await opened.last.query('storage_state')).single['active'], 0);
    expect(source.writes, isEmpty);
  });

  test(
    'Origen cambiado genera respaldo nuevo; no aplica candidato anterior',
    () async {
      seed();
      final failing = repository(
        checkpoint: (name) async {
          if (name == 'mapped') source.records = [];
        },
      );
      await expectLater(
        failing.loadSnapshot(),
        throwsA(isA<TreeStorageException>()),
      );
      expect((await repository().loadSnapshot())!.trees, isEmpty);
      expect(await backups.directory.list().toList(), hasLength(2));
    },
  );

  test(
    'Controlador actual confirma riego y carga historial tras reinicio',
    () async {
      seed(events: []);
      final now = DateTime.utc(2026, 11, 6);
      final controller = TreesController(
        repository: repo,
        clock: () => now,
        autoRefresh: false,
      );
      addTearDown(controller.dispose);
      expect(await controller.load(), isTrue);
      expect(await controller.water(tree.id), isTrue);
      expect(controller.eventsFor(), hasLength(1));
      final snapshot = (await repository().loadSnapshot())!;
      expect(snapshot.events.single.occurredAt, now);
      expect(snapshot.trees.single.ultimoRiego, now);
    },
  );

  test(
    'Perfil SQLite habilita claves foráneas y durabilidad completa',
    () async {
      source.records = [];
      await repo.loadSnapshot();
      final db = opened.last;
      expect(
        (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
        1,
      );
      expect((await db.rawQuery('PRAGMA synchronous')).single.values.single, 2);
      expect(
        (await db.rawQuery('PRAGMA journal_mode')).single.values.single,
        'delete',
      );
      await expectLater(
        db.insert('watering_events', {
          'space_id': 'anonymous',
          'id': 'invalido',
          'plant_ref_id': 'sin referencia',
          'position': 0,
          'plant_name_snapshot': 'Prueba',
          'occurred_at': '2026-01-01T00:00:00Z',
          'event_type': 'manual_registration',
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test('Web conserva repositorio anterior; nativos no validados no migran', () {
    expect(web.createTreeRepository(), isA<LocalTreeRepository>());
    expect(sqliteEnabledFor(StoragePlatform.android), isTrue);
    for (final platform in StoragePlatform.values.where(
      (p) => p != StoragePlatform.android,
    )) {
      expect(sqliteEnabledFor(platform), isFalse);
    }
  });

  test('Decodificador detecta fechas inválidas sin normalizarlas', () {
    for (final date in [
      '2026-13-01T12:00:00',
      '2026-01-01T25:00:00',
      'fecha',
    ]) {
      expect(
        () => MigrationSource.validateDate(date, requireZone: false),
        throwsFormatException,
      );
    }
  });
}
