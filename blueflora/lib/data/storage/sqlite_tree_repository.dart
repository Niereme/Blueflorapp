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
import 'local_schema_v2.dart';
import '../../domain/local_mutation.dart';

typedef StorageCheckpoint = Future<void> Function(String name);

/// Un escritor, confirmación transaccional y revisión local contra vistas obsoletas.
/// Contiene outbox local_only, sin cuentas, tokens ni acceso de red.
class SqliteTreeRepository extends TreeRepository {
  SqliteTreeRepository({
    required Future<Database> Function() openDatabase,
    required TreePreferencesStore source,
    required MigrationBackupStore backups,
    this.checkpoint,
    required this.spaceId,
  }) : _open = openDatabase,
       _source = source,
       _backups = backups;

  @override
  final String spaceId;
  @override
  int get revision => _revision ?? 0;
  final Map<String, int> _versions = {};
  @override
  int versionOf(String id) => _versions[id] ?? 0;
  final Future<Database> Function() _open;
  final TreePreferencesStore _source;
  final MigrationBackupStore _backups;
  final StorageCheckpoint? checkpoint;
  Database? _db;
  Future<void> _pending = Future.value();
  bool _loaded = false;
  int? _revision;
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

  static Future<void> upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion != 1 || newVersion != 2) {
      throw StateError('Versión no compatible.');
    }
    await upgradeLocalV2(db);
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
    if (version == 2) await upgradeLocalV2(db);
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
      final spaces = await db.query(
        'local_spaces',
        where: 'id=?',
        whereArgs: [spaceId],
      );
      if (spaces.length != 1 || spaces.single['kind'] != 'anonymous') {
        throw StateError('unknown_space');
      }
      // Ante corrupción/desaparición de una base activa NO volver al JSON viejo.
      var state = (await db.query('storage_state')).single;
      if (state['active'] != 1) {
        if (spaceId != 'anonymous') {
          throw StateError('Solo el anónimo incorpora preferencias.');
        }
        await _migrate(db);
        state = (await db.query('storage_state')).single;
      }
      if (state['e3_ready'] != 1) throw StateError('SQLite v2 no preparado.');
      _revision = state['revision'] as int;
      await _refreshVersions(db);
      final snapshot = state['initialized'] == 1 ? await _read(db) : null;
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
        await tx.update('storage_state', {'source_hash': hash}, where: 'id=1');
        await incorporatePriorState(tx, 'preferences_import');
        await tx.update('storage_state', {'e3_ready': 1}, where: 'id=1');
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
      where: "space_id=? AND deleted=0",
      whereArgs: [spaceId],
      orderBy: 'position',
    );
    final events = await db.query(
      'watering_events',
      where: "space_id=?",
      whereArgs: [spaceId],
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
    await tx.update(
      'plants',
      {'deleted': 1},
      where: 'space_id=?',
      whereArgs: [spaceId],
    );
    for (var i = 0; i < snapshot.trees.length; i++) {
      final tree = snapshot.trees[i];
      await tx.insert('plant_references', {
        'space_id': spaceId,
        'id': tree.id,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final date = tree.ultimoRiego?.toIso8601String();
      final values = {
        'space_id': spaceId,
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
        where: "space_id=? AND id=?",
        whereArgs: [spaceId, tree.id],
      );
      if (count == 0) await tx.insert('plants', values);
    }
    await checkpoint?.call('plants_written');
    final existing = await tx.query(
      'watering_events',
      where: "space_id=?",
      whereArgs: [spaceId],
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
        'space_id': spaceId,
        'id': event.plantId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final values = {
        'space_id': spaceId,
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
  Future<void> save(List<Tree> trees, {List<WateringEvent>? events}) async {
    throw TreeStorageException(
      'SQLite requiere una intención explícita; no admite guardar snapshots.',
    );
  }

  Future<void> _refreshVersions(DatabaseExecutor db) async {
    _versions.clear();
    for (final row in await db.query(
      'plants',
      where: 'space_id=?',
      whereArgs: [spaceId],
    )) {
      _versions[row['id'] as String] = row['local_version'] as int;
    }
  }

  @override
  Future<PlantSnapshot> applyMutation(
    LocalMutation mutation,
  ) => _serialize(() async {
    if (!_loaded || _db == null || !writable || mutation.spaceId != spaceId) {
      throw TreeStorageException('Carga el espacio correcto antes de guardar.');
    }
    try {
      late PlantSnapshot current;
      late int confirmedRevision;
      await _db!.transaction((tx) async {
        final identity = mutation.identityJson;
        final previous = await tx.query(
          'outbox',
          where: 'space_id=? AND operation_id=?',
          whereArgs: [spaceId, mutation.operationId],
        );
        final state = (await tx.query('storage_state')).single;
        if (previous.isNotEmpty) {
          if (previous.single['intent_json'] != identity ||
              previous.single['request_sha256'] != localHash(identity)) {
            throw StateError('operation_id_reused');
          }
          current = await _read(tx);
          confirmedRevision = state['revision'] as int;
          await _refreshVersions(tx);
          return;
        }
        if (state['active'] != 1 ||
            state['e3_ready'] != 1 ||
            state['revision'] != mutation.expectedRevision ||
            _revision != mutation.expectedRevision) {
          throw StateError('stale_global_revision');
        }
        final rows = await tx.query(
          'plants',
          where: 'space_id=? AND id=?',
          whereArgs: [spaceId, mutation.entityId],
        );
        final old = rows.isEmpty ? null : rows.single;
        if ((old?['local_version'] ?? 0) != mutation.expectedVersion) {
          throw StateError('stale_entity_version');
        }
        final nextVersion = incrementCounter(mutation.expectedVersion);
        confirmedRevision = incrementCounter(state['revision'] as int);
        final space = (await tx.query(
          'local_spaces',
          where: 'id=?',
          whereArgs: [spaceId],
        )).single;
        final sequence = space['next_local_sequence'] as int;
        final nextSequence = incrementCounter(sequence);
        final payload = mutation.payload;
        String? eventId;
        switch (mutation.action) {
          case 'plant.create':
            if (old != null) throw StateError('identity_unavailable');
            final tree = Tree.fromJson(payload);
            if (tree.id != mutation.entityId ||
                payload.keys
                    .toSet()
                    .difference(tree.toJson().keys.toSet())
                    .isNotEmpty) {
              throw StateError('invalid_create');
            }
            await tx.insert('plant_references', {
              'space_id': spaceId,
              'id': tree.id,
            });
            final date = tree.ultimoRiego?.toIso8601String();
            final kind = date == null
                ? 'unknown'
                : MigrationSource.hasZone(date)
                ? 'instant'
                : 'local_unzoned';
            final position =
                (await tx.rawQuery(
                      'SELECT COALESCE(MAX(position),-1) AS n FROM plants WHERE space_id=?',
                      [spaceId],
                    )).single['n']
                    as int;
            await tx.insert('plants', {
              'space_id': spaceId,
              'id': tree.id,
              'position': incrementCounter(position < 0 ? 0 : position),
              'name': tree.nombre,
              'species_label': tree.especie,
              'initial_height_m': tree.altura,
              'watering_frequency_days': tree.frecuenciaRiegoDias,
              'last_watered_text': date,
              'date_kind': kind,
              'baseline_text': date,
              'baseline_kind': kind,
              'baseline_source': date == null ? 'unknown' : 'declared_initial',
              'projection_mode': kind == 'local_unzoned'
                  ? 'legacy_hold'
                  : 'comparable',
              'local_version': nextVersion,
            });
            if (kind == 'local_unzoned') {
              await diagnose(tx, spaceId, tree.id, 'unresolved_local_time', {
                'original': date,
              }, operationId: mutation.operationId);
            }
          case 'plant.update':
            if (old == null || old['deleted'] == 1) {
              throw StateError('plant_not_active');
            }
            if (payload.keys.any(
              (key) => ![
                'nombre',
                'especie',
                'altura',
                'frecuenciaRiegoDias',
              ].contains(key),
            )) {
              throw StateError('invalid_profile_patch');
            }
            final tree = Tree.fromJson({
              'id': mutation.entityId,
              'nombre': old['name'],
              'especie': old['species_label'],
              'altura': old['initial_height_m'],
              'frecuenciaRiegoDias': old['watering_frequency_days'],
              ...payload,
            });
            await tx.update(
              'plants',
              {
                'name': tree.nombre,
                'species_label': tree.especie,
                'initial_height_m': tree.altura,
                'watering_frequency_days': tree.frecuenciaRiegoDias,
                'local_version': nextVersion,
              },
              where: 'space_id=? AND id=?',
              whereArgs: [spaceId, mutation.entityId],
            );
          case 'plant.delete':
            if (old == null || old['deleted'] == 1 || payload.isNotEmpty) {
              throw StateError('plant_not_active');
            }
            await tx.update(
              'plants',
              {'deleted': 1, 'local_version': nextVersion},
              where: 'space_id=? AND id=?',
              whereArgs: [spaceId, mutation.entityId],
            );
          case 'watering_event.append':
            if (old == null || old['deleted'] == 1) {
              throw StateError('plant_not_active');
            }
            MigrationSource.validateDate(
              payload['occurredAt'] as String,
              requireZone: true,
            );
            final event = WateringEvent.fromJson(payload);
            if (event.plantId != mutation.entityId ||
                payload.keys.toSet().difference({
                  ...event.toJson().keys,
                  'declarationText',
                }).isNotEmpty) {
              throw StateError('invalid_event');
            }
            eventId = event.id;
            final position =
                (await tx.rawQuery(
                      'SELECT COALESCE(MAX(position),0) AS n FROM watering_events WHERE space_id=?',
                      [spaceId],
                    )).single['n']
                    as int;
            await tx.insert('watering_events', {
              'space_id': spaceId,
              'id': event.id,
              'plant_ref_id': event.plantId,
              'position': incrementCounter(position),
              'plant_name_snapshot': event.plantName,
              'occurred_at': event.occurredAt.toIso8601String(),
              'event_type': 'manual_registration',
              'local_version': 1,
            });
            await checkpoint?.call('event_written');
            var projected = event.occurredAt;
            if (old['projection_mode'] == 'comparable' &&
                old['last_watered_text'] != null) {
              final before = DateTime.parse(old['last_watered_text'] as String);
              if (before.isAfter(projected)) {
                projected = before;
                await diagnose(
                  tx,
                  spaceId,
                  event.plantId,
                  'new_event_before_projection',
                  {'event': event.id},
                  operationId: mutation.operationId,
                );
              }
            }
            await tx.update(
              'plants',
              {
                'last_watered_text': projected.toIso8601String(),
                'date_kind': 'instant',
                'local_version': nextVersion,
              },
              where: 'space_id=? AND id=?',
              whereArgs: [spaceId, mutation.entityId],
            );
          default:
            throw StateError('unknown_action');
        }
        await checkpoint?.call('plants_written');
        await tx.insert('outbox', {
          'space_id': spaceId,
          'operation_id': mutation.operationId,
          'entity_type': eventId == null ? 'plant' : 'watering_event',
          'entity_id': eventId ?? mutation.entityId,
          'plant_ref_id': mutation.entityId,
          'action': mutation.action,
          'local_sequence': sequence,
          'entity_local_version': eventId == null ? nextVersion : 1,
          'intent_json': identity,
          'request_sha256': localHash(identity),
          'result_json': canonicalLocalJson({
            'revision': confirmedRevision,
            'plant_version': nextVersion,
            'event_id': eventId,
            'sequence': sequence,
          }),
          'status': 'local_only',
        });
        await checkpoint?.call('outbox_written');
        final prior = await tx.query(
          'outbox',
          columns: ['operation_id'],
          where: 'space_id=? AND plant_ref_id=? AND local_sequence<?',
          whereArgs: [spaceId, mutation.entityId, sequence],
          orderBy: 'local_sequence DESC',
          limit: 1,
        );
        if (prior.isNotEmpty) {
          await tx.insert('outbox_dependencies', {
            'space_id': spaceId,
            'operation_id': mutation.operationId,
            'depends_on': prior.single['operation_id'],
          });
        }
        await tx.update(
          'local_spaces',
          {'next_local_sequence': nextSequence},
          where: 'id=?',
          whereArgs: [spaceId],
        );
        await tx.update('storage_state', {
          'revision': confirmedRevision,
          'initialized': 1,
        }, where: 'id=1');
        await checkpoint?.call('before_save_commit');
        current = await _read(tx);
      });
      await checkpoint?.call('after_save_commit');
      _revision = confirmedRevision;
      await _refreshVersions(_db!);
      return current;
    } catch (error) {
      final code = error is StateError
          ? error.message.toString()
          : 'storage_failure';
      final explicit =
          [
            'operation_id_reused',
            'stale_global_revision',
            'stale_entity_version',
            'local_counter_exhausted',
          ].contains(code)
          ? ' ($code)'
          : '';
      throw TreeStorageException(
        'No se pudo confirmar la intención local$explicit; conserva el intento y reintenta o recarga.',
        error,
      );
    }
  });

  Future<void> close() => _serialize(() async {
    _loaded = false;
    await _db?.close();
    _db = null;
  });
}
