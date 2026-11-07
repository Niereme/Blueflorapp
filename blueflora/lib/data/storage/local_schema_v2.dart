import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../../domain/local_mutation.dart';

const maxLocalCounter = 9223372036854775807;
int incrementCounter(int value) {
  if (value < 0 || value >= maxLocalCounter) {
    throw StateError('local_counter_exhausted');
  }
  return value + 1;
}

String localHash(String text) => sha256.convert(utf8.encode(text)).toString();

/// Llamar dentro de onUpgrade/onCreate (transacción del motor).
Future<void> upgradeLocalV2(
  DatabaseExecutor db, {
  Future<void> Function(String)? checkpoint,
}) async {
  // Reconstruir solo las cuatro tablas relacionadas para liberar el ID de espacio.
  for (final table in [
    'plants',
    'watering_events',
    'plant_references',
    'local_spaces',
  ]) {
    await db.execute('ALTER TABLE $table RENAME TO ${table}_v1');
  }
  await db.execute(
    "CREATE TABLE local_spaces(id TEXT NOT NULL PRIMARY KEY, kind TEXT NOT NULL CHECK(kind='anonymous'), next_local_sequence INTEGER NOT NULL DEFAULT 1 CHECK(typeof(next_local_sequence)='integer' AND next_local_sequence>0))",
  );
  await db.execute(
    'INSERT INTO local_spaces(id,kind) SELECT id,kind FROM local_spaces_v1',
  );
  await db.execute(
    '''CREATE TABLE plant_references(space_id TEXT NOT NULL REFERENCES local_spaces(id), id TEXT NOT NULL,
    PRIMARY KEY(space_id,id))''',
  );
  await db.execute(
    'INSERT INTO plant_references SELECT * FROM plant_references_v1',
  );
  final originalPlants =
      (await db.query(
            "sqlite_master",
            columns: ['sql'],
            where: "name='plants_v1'",
          )).single['sql']
          as String;
  final originalEvents =
      (await db.query(
            "sqlite_master",
            columns: ['sql'],
            where: "name='watering_events_v1'",
          )).single['sql']
          as String;
  await db.execute(
    originalPlants
        .replaceAll('"plants_v1"', 'plants')
        .replaceAll('plant_references_v1', 'plant_references'),
  );
  await db.execute(
    originalEvents
        .replaceAll('"watering_events_v1"', 'watering_events')
        .replaceAll('plant_references_v1', 'plant_references'),
  );
  await db.execute('INSERT INTO plants SELECT * FROM plants_v1');
  await db.execute(
    'INSERT INTO watering_events SELECT * FROM watering_events_v1',
  );
  for (final table in [
    'plants',
    'watering_events',
    'plant_references',
    'local_spaces',
  ]) {
    final oldRows = await db.query(
      '${table}_v1',
      orderBy: table == 'local_spaces' ? 'id' : 'space_id,id',
    );
    final rows = await db.query(
      table,
      orderBy: table == 'local_spaces' ? 'id' : 'space_id,id',
    );
    final comparable = rows.map((row) {
      final copy = Map<String, Object?>.from(row);
      if (table == 'local_spaces') copy.remove('next_local_sequence');
      return copy;
    }).toList();
    if (canonicalLocalJson(oldRows) != canonicalLocalJson(comparable)) {
      throw StateError('La copia v2 difiere de v1.');
    }
  }
  for (final table in [
    'plants',
    'watering_events',
    'plant_references',
    'local_spaces',
  ]) {
    await db.execute('DROP TABLE ${table}_v1');
  }
  await db.execute(
    'CREATE INDEX event_plant_date ON watering_events(space_id,plant_ref_id,occurred_at)',
  );
  await db.execute(
    'CREATE INDEX visible_plants ON plants(space_id,deleted,position)',
  );
  await db.execute(
    'ALTER TABLE storage_state ADD COLUMN e3_ready INTEGER NOT NULL DEFAULT 0 CHECK(e3_ready IN (0,1))',
  );
  for (final table in ['plants', 'watering_events']) {
    await db.execute(
      'ALTER TABLE $table ADD COLUMN local_version INTEGER NOT NULL DEFAULT 1 CHECK(typeof(local_version)=\'integer\' AND local_version>0)',
    );
  }
  for (final column in [
    'baseline_text TEXT',
    "baseline_kind TEXT NOT NULL DEFAULT 'unknown' CHECK(baseline_kind IN ('unknown','instant','local_unzoned'))",
    "baseline_source TEXT NOT NULL DEFAULT 'unknown' CHECK(baseline_source IN ('unknown','legacy_snapshot','declared_initial'))",
    "projection_mode TEXT NOT NULL DEFAULT 'legacy_hold' CHECK(projection_mode IN ('comparable','legacy_hold'))",
  ]) {
    await db.execute('ALTER TABLE plants ADD COLUMN $column');
  }
  await db.execute('''CREATE TABLE prior_state_records(
    space_id TEXT NOT NULL REFERENCES local_spaces(id), record_kind TEXT NOT NULL CHECK(record_kind IN ('plants','plant_references','watering_events')),
    record_id TEXT NOT NULL, source_kind TEXT NOT NULL CHECK(source_kind IN ('sqlite_v1','preferences_import')),
    capture_version INTEGER NOT NULL CHECK(capture_version=1), source_revision INTEGER NOT NULL,
    source_hash TEXT, row_json TEXT NOT NULL, sha256 TEXT NOT NULL,
    PRIMARY KEY(space_id,record_kind,record_id))''');
  await db.execute(
    '''CREATE TABLE outbox(
    space_id TEXT NOT NULL REFERENCES local_spaces(id), operation_id TEXT NOT NULL,
    entity_type TEXT NOT NULL CHECK(entity_type IN ('plant','watering_event')), entity_id TEXT NOT NULL,
    plant_ref_id TEXT NOT NULL, action TEXT NOT NULL CHECK(action IN ('plant.create','plant.update','plant.delete','watering_event.append')),
    local_sequence INTEGER NOT NULL CHECK(typeof(local_sequence)='integer' AND local_sequence>0),
    entity_local_version INTEGER NOT NULL CHECK(entity_local_version>0),
    intent_json TEXT NOT NULL, request_sha256 TEXT NOT NULL, result_json TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status='local_only'),
    PRIMARY KEY(space_id,operation_id), UNIQUE(space_id,local_sequence),
    FOREIGN KEY(space_id,plant_ref_id) REFERENCES plant_references(space_id,id))''',
  );
  await db.execute(
    '''CREATE TABLE outbox_dependencies(
    space_id TEXT NOT NULL, operation_id TEXT NOT NULL, depends_on TEXT NOT NULL,
    PRIMARY KEY(space_id,operation_id,depends_on), CHECK(operation_id<>depends_on),
    FOREIGN KEY(space_id,operation_id) REFERENCES outbox(space_id,operation_id),
    FOREIGN KEY(space_id,depends_on) REFERENCES outbox(space_id,operation_id))''',
  );
  await db.execute(
    '''CREATE TRIGGER dependency_order BEFORE INSERT ON outbox_dependencies BEGIN
    SELECT CASE WHEN (SELECT local_sequence FROM outbox WHERE space_id=NEW.space_id AND operation_id=NEW.depends_on)
      >= (SELECT local_sequence FROM outbox WHERE space_id=NEW.space_id AND operation_id=NEW.operation_id)
    THEN RAISE(ABORT,'dependency_order') END; END''',
  );
  await db.execute(
    '''CREATE TABLE local_diagnostics(
    space_id TEXT NOT NULL, plant_id TEXT NOT NULL, code TEXT NOT NULL, operation_id TEXT NOT NULL DEFAULT '',
    detail_json TEXT NOT NULL, PRIMARY KEY(space_id,plant_id,code,operation_id),
    FOREIGN KEY(space_id,plant_id) REFERENCES plant_references(space_id,id))''',
  );
  for (final table in [
    'prior_state_records',
    'outbox',
    'outbox_dependencies',
    'watering_events',
  ]) {
    for (final action in ['UPDATE', 'DELETE']) {
      await db.execute(
        "CREATE TRIGGER immutable_${table}_${action.toLowerCase()} BEFORE $action ON $table BEGIN SELECT RAISE(ABORT,'immutable_$table'); END",
      );
    }
  }
  await db.execute(
    'CREATE INDEX queue_entity ON outbox(space_id,plant_ref_id,local_sequence)',
  );
  await checkpoint?.call('v2_schema');
  final state = (await db.query('storage_state')).single;
  if (state['active'] == 1) {
    await incorporatePriorState(db, 'sqlite_v1');
    await db.update('storage_state', {'e3_ready': 1}, where: 'id=1');
  }
  await verifyLocalIntegrity(db);
  await checkpoint?.call('v2_verified');
}

Future<void> verifyLocalIntegrity(DatabaseExecutor db) async {
  if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty ||
      (await db.rawQuery('PRAGMA integrity_check')).single.values.single !=
          'ok') {
    throw StateError('Falló integridad SQLite v2.');
  }
}

Future<void> diagnose(
  DatabaseExecutor db,
  String space,
  String plant,
  String code,
  Map<String, Object?> detail, {
  String operationId = '',
}) => db
    .insert('local_diagnostics', {
      'space_id': space,
      'plant_id': plant,
      'code': code,
      'operation_id': operationId,
      'detail_json': canonicalLocalJson(detail),
    }, conflictAlgorithm: ConflictAlgorithm.ignore)
    .then((_) {});

Future<void> incorporatePriorState(DatabaseExecutor db, String source) async {
  final state = (await db.query('storage_state')).single;
  for (final table in ['plant_references', 'plants', 'watering_events']) {
    for (final row in await db.query(table)) {
      final original = Map<String, Object?>.from(row);
      original.remove('local_version');
      for (final name in [
        'baseline_text',
        'baseline_kind',
        'baseline_source',
        'projection_mode',
      ]) {
        original.remove(name);
      }
      final json = canonicalLocalJson(original);
      await db.insert('prior_state_records', {
        'space_id': row['space_id'],
        'record_kind': table,
        'record_id': row['id'],
        'source_kind': source,
        'capture_version': 1,
        'source_revision': state['revision'],
        'source_hash': state['source_hash'],
        'row_json': json,
        'sha256': localHash(json),
      });
      final saved = (await db.query(
        'prior_state_records',
        where: 'space_id=? AND record_kind=? AND record_id=?',
        whereArgs: [row['space_id'], table, row['id']],
      )).single;
      if (saved['row_json'] != json || saved['sha256'] != localHash(json)) {
        throw StateError('Captura no verificada.');
      }
    }
  }
  for (final row in await db.query('plants')) {
    final text = row['last_watered_text'] as String?;
    final kind = row['date_kind'] as String;
    var hold = kind == 'local_unzoned';
    if (hold) {
      await diagnose(
        db,
        row['space_id'] as String,
        row['id'] as String,
        'unresolved_local_time',
        {'original': text},
      );
    }
    if (!hold) {
      final baseline = text == null ? null : DateTime.parse(text);
      for (final event in await db.query(
        'watering_events',
        where: 'space_id=? AND plant_ref_id=?',
        whereArgs: [row['space_id'], row['id']],
      )) {
        if (baseline == null ||
            DateTime.parse(event['occurred_at'] as String).isAfter(baseline)) {
          hold = true;
        }
      }
      if (hold) {
        await diagnose(
          db,
          row['space_id'] as String,
          row['id'] as String,
          'legacy_projection_mismatch',
          {'original': text},
        );
      }
    }
    await db.update(
      'plants',
      {
        'baseline_text': text,
        'baseline_kind': kind,
        'baseline_source': text == null ? 'unknown' : 'legacy_snapshot',
        'projection_mode': hold ? 'legacy_hold' : 'comparable',
      },
      where: 'space_id=? AND id=?',
      whereArgs: [row['space_id'], row['id']],
    );
  }
}
