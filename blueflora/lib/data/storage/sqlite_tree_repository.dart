import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/plant_snapshot.dart';
import '../../domain/tree.dart';
import '../../domain/watering_event.dart';
import '../../domain/unique_id.dart';
import '../local_tree_repository.dart';
import '../tree_repository.dart';
import 'migration_backup.dart';
import 'migration_source.dart';

typedef StorageCheckpoint = Future<void> Function(String name);

/// Un escritor, confirmación transaccional y revisión local contra vistas obsoletas.
/// No contiene cuentas, tokens, outbox ni acceso de red.
class SqliteTreeRepository extends TreeRepository {
  SqliteTreeRepository({
    required Future<Database> Function() openDatabase,
    required TreePreferencesStore source,
    required MigrationBackupStore backups,
    this.checkpoint,
  }) : _open = openDatabase,
       _source = source,
       _backups = backups;

  final Future<Database> Function() _open;
  final TreePreferencesStore _source;
  final MigrationBackupStore _backups;
  final StorageCheckpoint? checkpoint;
  Database? _db;
  Future<void> _pending = Future.value();
  bool _loaded = false;
  int? _revision;
  List<WateringEvent> _events = [];
  String? _notice;
  bool _readOnlySource = false;
  PlantSnapshot? _verifiedSource;
  String? _verifiedSourceEnvelope;
  @override
  bool get writable => !_readOnlySource;
  @override
  String? get storageNotice => _notice;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Perfil portable: no requiere JSON1, STRICT ni WAL.
  static Future<void> configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA busy_timeout = 5000');
    await db.rawQuery('PRAGMA journal_mode = DELETE');
    await db.execute('PRAGMA synchronous = FULL');
  }

  static Future<void> createSchema(Database db, int version) async {
    for (final sql in _schema) {
      await db.execute(sql);
    }
    await db.insert('storage_state', {
      'id': 1,
      'active': 0,
      'initialized': 0,
      'revision': 0,
      'database_id': createUniqueId(),
    });
  }

  static const _schema = [
    '''CREATE TABLE local_spaces (
      id TEXT PRIMARY KEY CHECK(id='anonymous'), kind TEXT NOT NULL CHECK(kind='anonymous'))''',
    "INSERT INTO local_spaces VALUES ('anonymous','anonymous')",
    '''CREATE TABLE storage_state (
      id INTEGER PRIMARY KEY CHECK(id=1), active INTEGER NOT NULL CHECK(active IN (0,1)),
      initialized INTEGER NOT NULL CHECK(initialized IN (0,1)),
      revision INTEGER NOT NULL CHECK(revision>=0), source_hash TEXT,
      database_id TEXT NOT NULL)''',
    '''CREATE TABLE recovery_backups (
      hash TEXT PRIMARY KEY, envelope TEXT NOT NULL)''',
    '''CREATE TABLE migration_runs (
      source_hash TEXT PRIMARY KEY REFERENCES recovery_backups(hash),
      state TEXT NOT NULL CHECK(state IN ('captured','mapped','active','blocked')),
      assigned_ids TEXT NOT NULL, diagnostics TEXT NOT NULL, error TEXT)''',
    '''CREATE TABLE plant_references (
      space_id TEXT NOT NULL REFERENCES local_spaces(id), id TEXT NOT NULL,
      PRIMARY KEY(space_id,id))''',
    '''CREATE TABLE plants (
      space_id TEXT NOT NULL, id TEXT NOT NULL, position INTEGER NOT NULL,
      name TEXT NOT NULL CHECK(length(name)>0), species_label TEXT,
      initial_height_m REAL CHECK(initial_height_m IS NULL OR initial_height_m>0),
      watering_frequency_days INTEGER NOT NULL CHECK(typeof(watering_frequency_days)='integer'
        AND watering_frequency_days BETWEEN 1 AND 36500),
      last_watered_text TEXT, date_kind TEXT NOT NULL CHECK(date_kind IN ('unknown','local_unzoned','instant')),
      deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1)),
      PRIMARY KEY(space_id,id),
      FOREIGN KEY(space_id,id) REFERENCES plant_references(space_id,id))''',
    '''CREATE TABLE watering_events (
      space_id TEXT NOT NULL, id TEXT NOT NULL, plant_ref_id TEXT NOT NULL,
      position INTEGER NOT NULL, plant_name_snapshot TEXT NOT NULL,
      occurred_at TEXT NOT NULL, event_type TEXT NOT NULL CHECK(event_type='manual_registration'),
      PRIMARY KEY(space_id,id),
      FOREIGN KEY(space_id,plant_ref_id) REFERENCES plant_references(space_id,id))''',
    'CREATE INDEX event_plant_date ON watering_events(space_id,plant_ref_id,occurred_at)',
    'CREATE INDEX visible_plants ON plants(space_id,deleted,position)',
  ];

  @override
  Future<PlantSnapshot?> loadSnapshot() => _serialize(() async {
    _loaded = false;
    _readOnlySource = false;
    _verifiedSource = null;
    _verifiedSourceEnvelope = null;
    try {
      final db = _db ??= await _open();
      // Ante corrupción/desaparición de una base activa NO volver al JSON viejo.
      var state = (await db.query('storage_state')).single;
      if (state['active'] != 1) {
        await _migrate(db);
        state = (await db.query('storage_state')).single;
      }
      _revision = state['revision'] as int;
      final snapshot = state['initialized'] == 1 ? await _read(db) : null;
      _events = List.of(snapshot?.events ?? []);
      final runs = await db.query(
        'migration_runs',
        where: 'source_hash=?',
        whereArgs: [state['source_hash']],
      );
      _notice =
          runs.isNotEmpty &&
              (jsonDecode(runs.single['diagnostics'] as String) as List)
                  .isNotEmpty
          ? 'Se conservaron datos locales sin transformarlos. Hay un diagnóstico de migración disponible en el respaldo local.'
          : null;
      _loaded = true;
      return snapshot;
    } catch (error) {
      final candidate = _verifiedSource;
      if (candidate != null && _db != null) {
        // Solo una comprobación positiva de no-activación permite usar el origen.
        // Si no podemos consultar el marcador, fallar cerrado.
        try {
          final state = (await _db!.query('storage_state')).single;
          if (state['active'] == 0 &&
              MigrationSource(await _source.read()).envelope ==
                  _verifiedSourceEnvelope) {
            _events = List.of(candidate.events);
            _readOnlySource = true;
            _loaded = true;
            _notice =
                'La migración está pendiente. Se muestran los datos originales en modo de solo lectura para conservarlos. Reintenta la migración.';
            return candidate;
          }
        } catch (_) {
          // Una base activa o ilegible nunca se sustituye por preferencias viejas.
        }
      }
      throw TreeStorageException(
        'No se pudo abrir o migrar el almacenamiento local. El origen y los respaldos se conservan. Reintenta; no borres los datos de la aplicación.',
        error,
      );
    }
  });

  Future<void> _migrate(Database db) async {
    final raw = await _source.read();
    final source = MigrationSource(raw == null ? null : List.of(raw));
    final envelope = source.envelope;
    final hash = sha256.convert(utf8.encode(envelope)).toString();
    await _backups.capture(hash, envelope);
    if (await _backups.read(hash) != envelope) {
      throw StateError('Respaldo incompleto.');
    }
    await db.transaction((tx) async {
      await tx.insert('recovery_backups', {
        'hash': hash,
        'envelope': envelope,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final saved = (await tx.query(
        'recovery_backups',
        where: 'hash=?',
        whereArgs: [hash],
      )).single;
      if (saved['envelope'] != envelope) {
        throw StateError('Origen distinto del respaldo.');
      }
      await tx.insert('migration_runs', {
        'source_hash': hash,
        'state': 'captured',
        'assigned_ids': '{}',
        'diagnostics': '[]',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    await checkpoint?.call('captured');
    try {
      final run = (await db.query(
        'migration_runs',
        where: 'source_hash=?',
        whereArgs: [hash],
      )).single;
      final assigned = Map<String, String>.from(
        jsonDecode(run['assigned_ids'] as String) as Map,
      );
      final snapshot = source.decode(assigned);
      // El mapeo se confirma antes de intentar poblar tablas: estable al reintentar.
      await db.update(
        'migration_runs',
        {
          'state': 'mapped',
          'assigned_ids': jsonEncode(assigned),
          'diagnostics': jsonEncode(source.diagnostics),
          'error': null,
        },
        where: 'source_hash=?',
        whereArgs: [hash],
      );
      _verifiedSource = snapshot;
      _verifiedSourceEnvelope = envelope;
      await checkpoint?.call('mapped');
      // No activar un candidato si cambió el origen durante la preparación.
      final latest = MigrationSource(await _source.read()).envelope;
      if (latest != envelope) {
        throw StateError(
          'El origen cambió; reintenta para capturar un respaldo nuevo.',
        );
      }
      await db.transaction((tx) async {
        if ((await tx.query('storage_state')).single['active'] == 1) return;
        await _write(tx, snapshot ?? PlantSnapshot(trees: []));
        await checkpoint?.call('staged');
        final readBack = await _read(tx);
        if (jsonEncode(readBack.toJson()) !=
            jsonEncode((snapshot ?? PlantSnapshot(trees: [])).toJson())) {
          throw StateError('La lectura no coincide con los datos migrados.');
        }
        if ((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty ||
            (await tx.rawQuery(
                  'PRAGMA integrity_check',
                )).single.values.single !=
                'ok') {
          throw StateError('Falló la verificación de integridad.');
        }
        await checkpoint?.call('verified');
        await tx.update('storage_state', {
          'active': 1,
          'initialized': snapshot == null ? 0 : 1,
          'source_hash': hash,
        }, where: 'id=1');
        await tx.update(
          'migration_runs',
          {'state': 'active'},
          where: 'source_hash=?',
          whereArgs: [hash],
        );
      });
      await checkpoint?.call('activated');
    } catch (error) {
      // No degradar un COMMIT ya confirmado si se perdió su respuesta.
      if ((await db.query('storage_state')).single['active'] != 1) {
        await db.update(
          'migration_runs',
          {
            'state': 'blocked',
            'diagnostics': jsonEncode(source.diagnostics),
            'error':
                'Migración no activada: ${error.runtimeType}. Origen conservado.',
          },
          where: 'source_hash=?',
          whereArgs: [hash],
        );
      }
      rethrow;
    }
  }

  Future<PlantSnapshot> _read(DatabaseExecutor db) async {
    final trees = await db.query(
      'plants',
      where: "space_id='anonymous' AND deleted=0",
      orderBy: 'position',
    );
    final events = await db.query(
      'watering_events',
      where: "space_id='anonymous'",
      orderBy: 'position',
    );
    return PlantSnapshot(
      trees: trees.map(
        (row) => Tree.fromJson({
          'id': row['id'],
          'nombre': row['name'],
          'especie': row['species_label'],
          'altura': row['initial_height_m'],
          'frecuenciaRiegoDias': row['watering_frequency_days'],
          'ultimoRiego': row['last_watered_text'],
        }),
      ),
      events: events.map(
        (row) => WateringEvent.fromJson({
          'id': row['id'],
          'plantId': row['plant_ref_id'],
          'plantName': row['plant_name_snapshot'],
          'occurredAt': row['occurred_at'],
          'type': row['event_type'],
        }),
      ),
    );
  }

  Future<void> _write(DatabaseExecutor tx, PlantSnapshot snapshot) async {
    // El borrado visible mantiene filas históricas y referencias sin crear plantas.
    await tx.update('plants', {'deleted': 1}, where: "space_id='anonymous'");
    for (var i = 0; i < snapshot.trees.length; i++) {
      final tree = snapshot.trees[i];
      await tx.insert('plant_references', {
        'space_id': 'anonymous',
        'id': tree.id,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final date = tree.ultimoRiego?.toIso8601String();
      final values = {
        'space_id': 'anonymous',
        'id': tree.id,
        'position': i,
        'name': tree.nombre,
        'species_label': tree.especie,
        'initial_height_m': tree.altura,
        'watering_frequency_days': tree.frecuenciaRiegoDias,
        'last_watered_text': date,
        'date_kind': date == null
            ? 'unknown'
            : MigrationSource.hasZone(date)
            ? 'instant'
            : 'local_unzoned',
        'deleted': 0,
      };
      final count = await tx.update(
        'plants',
        values,
        where: "space_id='anonymous' AND id=?",
        whereArgs: [tree.id],
      );
      if (count == 0) await tx.insert('plants', values);
    }
    await checkpoint?.call('plants_written');
    final existing = await tx.query(
      'watering_events',
      where: "space_id='anonymous'",
    );
    final supplied = snapshot.events.map((event) => event.id).toSet();
    if (existing.any((row) => !supplied.contains(row['id']))) {
      throw StateError(
        'No se puede descartar historial existente. Recarga los datos.',
      );
    }
    for (var i = 0; i < snapshot.events.length; i++) {
      final event = snapshot.events[i];
      await tx.insert('plant_references', {
        'space_id': 'anonymous',
        'id': event.plantId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final values = {
        'space_id': 'anonymous',
        'id': event.id,
        'plant_ref_id': event.plantId,
        'position': i,
        'plant_name_snapshot': event.plantName,
        'occurred_at': event.occurredAt.toIso8601String(),
        'event_type': 'manual_registration',
      };
      final old = existing.where((row) => row['id'] == event.id);
      if (old.isEmpty) {
        await tx.insert('watering_events', values);
      } else {
        for (final field in [
          'plant_ref_id',
          'plant_name_snapshot',
          'occurred_at',
          'event_type',
        ]) {
          if (old.single[field] != values[field]) {
            throw StateError('No se puede sobrescribir un evento histórico.');
          }
        }
      }
    }
  }

  @override
  Future<void> save(List<Tree> trees, {List<WateringEvent>? events}) {
    final treeCopy = List<Tree>.of(trees);
    final eventCopy = events == null ? null : List<WateringEvent>.of(events);
    return _serialize(() async {
      if (!_loaded || _db == null || !writable) {
        throw TreeStorageException(
          'Debes completar la carga y la migración antes de guardar.',
        );
      }
      try {
        final snapshot = PlantSnapshot(
          trees: treeCopy,
          events: eventCopy ?? _events,
        );
        await _db!.transaction((tx) async {
          final state = (await tx.query('storage_state')).single;
          if (state['active'] != 1 || state['revision'] != _revision) {
            throw StateError(
              'La versión local cambió. Recarga antes de guardar.',
            );
          }
          await _write(tx, snapshot);
          await checkpoint?.call('before_save_commit');
          await tx.update('storage_state', {
            'initialized': 1,
            'revision': _revision! + 1,
          }, where: 'id=1');
        });
        _revision = _revision! + 1;
        _events = List.of(snapshot.events);
      } catch (error) {
        throw TreeStorageException(
          'No se pudieron guardar los cambios. Los datos confirmados se conservan; reintenta o recarga.',
          error,
        );
      }
    });
  }

  Future<void> close() => _serialize(() async {
    _loaded = false;
    await _db?.close();
    _db = null;
  });
}
