# SQLite local v1, compatibilidad y migración

**Esquema de diseño; no es una migración ejecutable ni cambia Flutter.** Los
nombres siguientes son internos; la interfaz sigue usando repositorios y modelos.

## 1. Plataformas realmente presentes

El repositorio contiene android/, ios/, macos/, linux/, windows/ y web/. Su presencia
no demuestra que todas las compilaciones o plugins estén validados. El adaptador
actual de recordatorios solo implementa programación en Android; no ampliar esa
promesa por introducir SQLite.

| Plataforma | Diseño de persistencia | Condición antes de habilitar |
| --- | --- | --- |
| Android | API común SQLite con sqflite | Pruebas instrumentadas de transacción/cierre y versión del motor |
| iOS/macOS | Mismo DAO sobre sqflite | Verificar sandbox, backup y almacén seguro en esos sistemas |
| Linux/Windows | Mismo DAO sobre sqflite_common_ffi | Pruebas reales de filesystem, SQLite nativo y protección de tokens |
| Web | Adaptador distinto; NO aprobar automáticamente el experimental | Validar IndexedDB/WASM, cuotas, expulsión, cierre, pestañas y seguridad frente a XSS |

sqflite documenta Android/iOS/macOS; sqflite_common_ffi documenta Linux/Windows.
El adaptador web se declara experimental, requiere WASM/worker y tiene limitaciones
de bloqueo según navegador. No se puede afirmar igual durabilidad que en Android.
Para 3.2E.2 se propone validar Android y Linux, conservar el comportamiento actual
en otros targets sin activar la migración allí hasta validar el adaptador. No
introducir imports dart:ffi en web. Ningún paquete, versión o requisito apt queda
instalado por este diseño: comprobar compatibilidad con el SDK Dart ^3.9.2 antes
de seleccionar versiones. No actualizar SDK ni Gradle como efecto secundario.

## 2. Tipos y garantías locales

- Una base local privada con múltiples espacios. Todo dato personal tiene space_id;
  claves/relaciones compuestas impiden mezclar espacios incluso con UUID iguales.
- UUID canónicos TEXT; UTC como TEXT RFC3339 fijo a seis decimales y sufijo Z.
  Revisión remota TEXT decimal canónica (se compara por igualdad/BigInt, no orden
  lexicográfico); contadores locales INTEGER de 64 bits. Nombres Unicode íntegros.
- SQLite REAL para dimensiones, INTEGER para frecuencia. DAO rechaza bool, NaN e
  infinitos ANTES de bind: algunos drivers convierten NaN a NULL; un CHECK nullable
  no basta. Conservar originales incompatibles fuera de tablas normalizadas.
- Toda conexión verifica foreign_keys=ON, synchronous=FULL y busy_timeout=5000;
  journal_mode=DELETE como perfil v1 portable. No journal OFF/MEMORY ni synchronous
  OFF/NORMAL. Un escritor coordinado; no transacciones abiertas durante HTTP.
- Perfil WAL es una optimización posterior que requiere pruebas de checkpoint y
  backup de la base+WAL. Nunca copiar solo el archivo DB mientras está abierto.
  Ni SQLite garantiza supervivencia frente a hardware que mienta sobre fsync;
  las garantías dependen de las condiciones documentadas del sistema de archivos.
- La versión de este modelo objetivo no es PRAGMA user_version ni protocol_version.
  Cada entrega implementará solo las tablas autorizadas mediante revisiones locales
  crecientes; E.2 no activa red, bootstrap ni cuentas por crear su estructura futura.
- No requerir SQLite STRICT, JSON1 o extensiones específicas del motor. JSON en
  TEXT se valida por DAO; no poner secretos en JSON ni en migraciones locales.
- El sandbox del SO protege archivos; SQLite ordinario NO cifra los datos.
  Espacios bloqueados son una protección de aplicación, no defensa frente a root
  o copia forense de la base. Ver decisiones de seguridad antes de datos reales.

## 3. Esquema relacional local v1

DDL de referencia del esquema v1 propuesto para aprobación; NO ejecutar en la base del usuario.
Se incluyen índices posteriores. Restricciones UUID/UTC, JSON, finitud, tipos y
máximos Unicode requieren además los validadores del DAO descritos arriba.

```sql
CREATE TABLE local_spaces (
  id TEXT NOT NULL PRIMARY KEY,
  kind TEXT NOT NULL CHECK(kind IN ('anonymous','account')),
  server_instance_id TEXT,
  user_id TEXT,
  installation_id TEXT,
  access_state TEXT NOT NULL CHECK(access_state IN ('open','locked')),
  auth_epoch INTEGER NOT NULL DEFAULT 0 CHECK(auth_epoch >= 0),
  next_local_sequence INTEGER NOT NULL DEFAULT 1 CHECK(next_local_sequence > 0),
  created_at TEXT NOT NULL,
  CHECK((kind='anonymous' AND user_id IS NULL AND server_instance_id IS NULL AND installation_id IS NULL)
     OR (kind='account' AND user_id IS NOT NULL AND server_instance_id IS NOT NULL AND installation_id IS NOT NULL)),
  UNIQUE(server_instance_id,user_id)
);
CREATE UNIQUE INDEX one_anonymous_space ON local_spaces(kind) WHERE kind='anonymous';

CREATE TABLE gardens (
  space_id TEXT NOT NULL REFERENCES local_spaces(id) ON DELETE RESTRICT,
  id TEXT NOT NULL, name TEXT NOT NULL, description TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
  local_version INTEGER NOT NULL CHECK(local_version > 0), server_revision TEXT,
  PRIMARY KEY(space_id,id)
);
CREATE TABLE species (
  space_id TEXT NOT NULL REFERENCES local_spaces(id) ON DELETE RESTRICT,
  id TEXT NOT NULL, scientific_name TEXT NOT NULL, common_name TEXT,
  description TEXT, source TEXT, catalog_version TEXT NOT NULL,
  PRIMARY KEY(space_id,id)
);
CREATE TABLE plant_references (
  space_id TEXT NOT NULL REFERENCES local_spaces(id) ON DELETE RESTRICT,
  id TEXT NOT NULL,
  state TEXT NOT NULL CHECK(state IN ('full','historical_only')),
  server_revision TEXT,
  PRIMARY KEY(space_id,id)
);
CREATE TABLE plants (
  space_id TEXT NOT NULL, id TEXT NOT NULL,
  garden_id TEXT, species_id TEXT,
  name TEXT NOT NULL, species_label TEXT,
  initial_height_m REAL CHECK(initial_height_m IS NULL OR (initial_height_m > 0 AND initial_height_m <= 1.7976931348623157e308)),
  watering_frequency_days INTEGER NOT NULL CHECK(typeof(watering_frequency_days)='integer' AND watering_frequency_days BETWEEN 1 AND 36500),
  baseline_last_watered_at TEXT, baseline_source TEXT NOT NULL
    CHECK(baseline_source IN ('unknown','legacy_registration','legacy_snapshot','declared_initial')),
  last_watered_at TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
  origin TEXT NOT NULL CHECK(origin IN ('local','legacy','remote','demo')),
  local_version INTEGER NOT NULL CHECK(local_version > 0), server_revision TEXT,
  PRIMARY KEY(space_id,id),
  FOREIGN KEY(space_id,id) REFERENCES plant_references(space_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(space_id,garden_id) REFERENCES gardens(space_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(space_id,species_id) REFERENCES species(space_id,id) ON DELETE RESTRICT
);
CREATE TABLE watering_events (
  space_id TEXT NOT NULL, id TEXT NOT NULL, plant_id TEXT, plant_ref_id TEXT NOT NULL,
  plant_name_snapshot TEXT NOT NULL, occurred_at TEXT NOT NULL, recorded_at TEXT,
  event_type TEXT NOT NULL CHECK(event_type='manual'),
  local_version INTEGER NOT NULL CHECK(local_version > 0), server_revision TEXT,
  PRIMARY KEY(space_id,id),
  CHECK(plant_id IS NULL OR plant_id=plant_ref_id),
  FOREIGN KEY(space_id,plant_ref_id) REFERENCES plant_references(space_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(space_id,plant_id) REFERENCES plants(space_id,id) ON DELETE RESTRICT
);
CREATE TABLE growth_history (
  space_id TEXT NOT NULL, id TEXT NOT NULL, plant_id TEXT, plant_ref_id TEXT NOT NULL,
  plant_name_snapshot TEXT NOT NULL, measured_at TEXT NOT NULL, recorded_at TEXT,
  height_m REAL CHECK(height_m IS NULL OR (height_m > 0 AND height_m <= 1.7976931348623157e308)),
  diameter_m REAL CHECK(diameter_m IS NULL OR (diameter_m > 0 AND diameter_m <= 1.7976931348623157e308)),
  diameter_kind TEXT, notes TEXT,
  local_version INTEGER NOT NULL CHECK(local_version > 0), server_revision TEXT,
  PRIMARY KEY(space_id,id),
  CHECK(height_m IS NOT NULL OR diameter_m IS NOT NULL),
  CHECK((diameter_m IS NULL AND diameter_kind IS NULL) OR
        (diameter_m IS NOT NULL AND diameter_kind IS NOT NULL AND diameter_kind IN ('stem','canopy'))),
  CHECK(plant_id IS NULL OR plant_id=plant_ref_id),
  FOREIGN KEY(space_id,plant_ref_id) REFERENCES plant_references(space_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(space_id,plant_id) REFERENCES plants(space_id,id) ON DELETE RESTRICT
);

CREATE TABLE outbox (
  space_id TEXT NOT NULL REFERENCES local_spaces(id) ON DELETE RESTRICT,
  operation_id TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
  action TEXT NOT NULL, local_sequence INTEGER NOT NULL CHECK(local_sequence > 0),
  entity_local_version INTEGER NOT NULL CHECK(entity_local_version > 0),
  base_revision TEXT, draft_payload_json TEXT NOT NULL,
  frozen_request_json TEXT, request_sha256 TEXT,
  status TEXT NOT NULL CHECK(status IN ('local_only','draft','ready','in_flight','acked','conflict','rejected','blocked','superseded')),
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK(attempt_count >= 0),
  next_attempt_at TEXT, last_error_code TEXT, created_at TEXT NOT NULL,
  supersedes_operation_id TEXT,
  PRIMARY KEY(space_id,operation_id), UNIQUE(space_id,local_sequence),
  CHECK((frozen_request_json IS NULL AND request_sha256 IS NULL) OR
        (frozen_request_json IS NOT NULL AND request_sha256 IS NOT NULL)),
  FOREIGN KEY(space_id,supersedes_operation_id) REFERENCES outbox(space_id,operation_id) ON DELETE RESTRICT
);
CREATE TABLE outbox_dependencies (
  space_id TEXT NOT NULL, operation_id TEXT NOT NULL, depends_on TEXT NOT NULL,
  PRIMARY KEY(space_id,operation_id,depends_on), CHECK(operation_id<>depends_on),
  FOREIGN KEY(space_id,operation_id) REFERENCES outbox(space_id,operation_id) ON DELETE RESTRICT,
  FOREIGN KEY(space_id,depends_on) REFERENCES outbox(space_id,operation_id) ON DELETE RESTRICT
);
CREATE TABLE server_shadows (
  space_id TEXT NOT NULL REFERENCES local_spaces(id) ON DELETE RESTRICT,
  entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, revision TEXT NOT NULL,
  state_json TEXT NOT NULL, server_sequence TEXT NOT NULL,
  PRIMARY KEY(space_id,entity_type,entity_id)
);
CREATE TABLE operation_receipts (
  space_id TEXT NOT NULL, operation_id TEXT NOT NULL,
  request_sha256 TEXT NOT NULL, receipt_json TEXT NOT NULL, received_at TEXT NOT NULL,
  PRIMARY KEY(space_id,operation_id),
  FOREIGN KEY(space_id,operation_id) REFERENCES outbox(space_id,operation_id) ON DELETE RESTRICT
);
CREATE TABLE sync_state (
  space_id TEXT NOT NULL PRIMARY KEY REFERENCES local_spaces(id) ON DELETE RESTRICT,
  protocol_version INTEGER NOT NULL CHECK(protocol_version=1),
  change_epoch TEXT, changes_cursor TEXT, last_applied_sequence TEXT,
  catalog_version TEXT, last_success_at TEXT,
  state TEXT NOT NULL CHECK(state IN ('disabled','idle','syncing','needs_login','needs_bootstrap','attention'))
);
CREATE TABLE applied_change_groups (
  space_id TEXT NOT NULL REFERENCES local_spaces(id) ON DELETE RESTRICT,
  change_epoch TEXT NOT NULL, sequence TEXT NOT NULL, change_id TEXT NOT NULL,
  PRIMARY KEY(space_id,change_epoch,sequence), UNIQUE(space_id,change_id)
);
CREATE TABLE conflicts (
  space_id TEXT NOT NULL, id TEXT NOT NULL,
  operation_id TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
  base_json TEXT, local_json TEXT NOT NULL, remote_json TEXT,
  remote_revision TEXT, reason TEXT NOT NULL,
  resolution TEXT CHECK(resolution IN ('local','remote','merged','copied')),
  replacement_operation_id TEXT, resolved_at TEXT,
  PRIMARY KEY(space_id,id),
  FOREIGN KEY(space_id,operation_id) REFERENCES outbox(space_id,operation_id) ON DELETE RESTRICT,
  FOREIGN KEY(space_id,replacement_operation_id) REFERENCES outbox(space_id,operation_id) ON DELETE RESTRICT
);
CREATE TABLE bootstrap_staging (
  space_id TEXT NOT NULL REFERENCES local_spaces(id) ON DELETE RESTRICT,
  bootstrap_id TEXT NOT NULL, page_index INTEGER NOT NULL CHECK(page_index >= 0),
  page_json TEXT NOT NULL, page_sha256 TEXT NOT NULL,
  next_page_cursor TEXT, expires_at TEXT NOT NULL,
  PRIMARY KEY(space_id,bootstrap_id,page_index)
);
CREATE TABLE link_imports (
  space_id TEXT NOT NULL REFERENCES local_spaces(id) ON DELETE RESTRICT,
  import_id TEXT NOT NULL, manifest_json TEXT NOT NULL,
  consent_version TEXT NOT NULL, consent_selection_sha256 TEXT NOT NULL,
  status TEXT NOT NULL, next_record_index INTEGER NOT NULL DEFAULT 0,
  progress_json TEXT NOT NULL,
  PRIMARY KEY(space_id,import_id)
);
CREATE TABLE link_import_records (
  space_id TEXT NOT NULL, import_id TEXT NOT NULL, record_index INTEGER NOT NULL,
  operation_id TEXT NOT NULL, source_record_id TEXT,
  record_json TEXT NOT NULL, receipt_json TEXT,
  PRIMARY KEY(space_id,import_id,record_index), UNIQUE(space_id,operation_id),
  FOREIGN KEY(space_id,import_id) REFERENCES link_imports(space_id,import_id) ON DELETE RESTRICT,
  FOREIGN KEY(space_id,operation_id) REFERENCES outbox(space_id,operation_id) ON DELETE RESTRICT
);

CREATE TABLE recovery_backups (
  id TEXT NOT NULL PRIMARY KEY, source_key TEXT NOT NULL, key_present INTEGER NOT NULL CHECK(key_present IN (0,1)),
  envelope_utf8 BLOB NOT NULL, sha256 TEXT NOT NULL, created_at TEXT NOT NULL,
  verified_at TEXT, UNIQUE(source_key,sha256)
);
CREATE TABLE migration_runs (
  id TEXT NOT NULL PRIMARY KEY, backup_id TEXT NOT NULL REFERENCES recovery_backups(id) ON DELETE RESTRICT,
  target_schema_version INTEGER NOT NULL, status TEXT NOT NULL,
  source_count INTEGER NOT NULL, normalized_count INTEGER NOT NULL DEFAULT 0,
  issue_count INTEGER NOT NULL DEFAULT 0, started_at TEXT NOT NULL, activated_at TEXT,
  UNIQUE(backup_id,target_schema_version)
);
CREATE TABLE legacy_records (
  id TEXT NOT NULL PRIMARY KEY, migration_id TEXT NOT NULL REFERENCES migration_runs(id) ON DELETE RESTRICT,
  record_kind TEXT NOT NULL, source_index INTEGER NOT NULL,
  raw_json TEXT NOT NULL, original_identifier TEXT, status TEXT NOT NULL,
  issue_json TEXT, UNIQUE(migration_id,record_kind,source_index)
);
CREATE TABLE identifier_resolutions (
  legacy_record_id TEXT NOT NULL PRIMARY KEY REFERENCES legacy_records(id) ON DELETE RESTRICT,
  resolved_uuid TEXT NOT NULL, reason TEXT NOT NULL, confirmed_at TEXT,
  mapping_json TEXT NOT NULL
);
CREATE TABLE date_resolutions (
  legacy_record_id TEXT NOT NULL REFERENCES legacy_records(id) ON DELETE RESTRICT,
  field_name TEXT NOT NULL, raw_value TEXT NOT NULL,
  resolved_utc TEXT, assumed_zone TEXT, confirmed_at TEXT,
  PRIMARY KEY(legacy_record_id,field_name)
);
CREATE TABLE storage_metadata (
  key TEXT NOT NULL PRIMARY KEY, value_json TEXT NOT NULL
);

CREATE INDEX plants_active ON plants(space_id,deleted_at);
CREATE INDEX plants_garden ON plants(space_id,garden_id);
CREATE INDEX events_by_plant ON watering_events(space_id,plant_ref_id,occurred_at,id);
CREATE INDEX events_by_date ON watering_events(space_id,occurred_at,id);
CREATE INDEX growth_by_plant ON growth_history(space_id,plant_ref_id,measured_at,id);
CREATE INDEX growth_by_date ON growth_history(space_id,measured_at,id);
CREATE INDEX queue_ready ON outbox(space_id,status,next_attempt_at,local_sequence);
CREATE INDEX queue_entity ON outbox(space_id,entity_type,entity_id,local_sequence);
CREATE INDEX conflicts_pending ON conflicts(space_id,resolved_at);
```

created_at/updated_at de filas aún no confirmadas son tiempos de la fila local,
no afirmaciones de la fecha original de registro de una planta legada; esa fecha
original es desconocida. Los tiempos del servidor viven en shadows y reemplazan
la proyección remota al confirmar; nunca se mandan tiempos locales como autoridad.
No claves de autenticación, contraseñas o refresh tokens en ninguna tabla. Los
archivos de backup pertenecen al sandbox de la app; no publicar/exportar sin acción
explícita. Los backups no se eliminan por logout. Si se decide cifrar SQLite en
reposo, esos backups y staging deben quedar cubiertos también.

### Invariantes de actualización local

- Repositorio transaccional actualiza entidad/local_version, evento si procede,
  outbox y next_local_sequence juntos. En anónimo el comando es local_only, no
  elegible para red. Vincular crea operaciones import explícitas, no manda el log
  completo de ediciones anónimas previas.
- No hacer UPSERT que reemplace una fila sucia con el servidor. Actualizar shadow
  y rebasar borradores; si no es inequívoco, persistir conflicto con tres versiones.
- Congelar envelope y fingerprint antes de sacar el comando de draft/ready. Un
  cierre con in_flight se recupera reintentando el mismo request. No asignar otra
  operación solo por timeout. next_attempt_at sirve a scheduling, no a prioridad
  de conflicto; cambios del reloj no deciden ganadores.
- local_sequence ordena causalidad del dispositivo; no se usa como orden global.
  Validar DAG de dependencias en DAO. Por entidad solo un comando en vuelo. No
  colapsar comandos ya enviados; se permite superseder borradores no enviados
  dejando rastro de los cambios y sin borrar eventos.
- ACK + receipt + shadow + resultado de rebase es una sola transacción. Un ACK
  antiguo marca su operación, pero no retrocede una revisión más nueva descargada.
- Cursor y grupos aplicados se guardan juntos. Páginas incompletas solo staging.
- last_watered_at local se deriva del baseline y eventos visibles, incluidos
  pendientes, sin depender de recorded_at del servidor. Una fecha rechazada se
  conserva con conflicto; la UI distingue declaración pendiente/confirmada.
- Un controlador compartido por espacio, sin repositorios por pantalla. Recalcular
  recordatorios solo después de COMMIT, con registro de avisos separado por espacio.
  IDs Android de notificación no se suben a la nube.

## 4. Mapeo exacto del legado

| Fuente real Flutter | Destino SQLite / DTO sync | Condición |
| --- | --- | --- |
| Tree.id | plants.id, plant_references.id | UUID existente se conserva; no deduplicar por nombre |
| nombre | name | No vacío; 200 puntos Unicode remoto, local original siempre preservado |
| especie | species_label | Texto libre; species_id=null si no existía |
| altura | initial_height_m | Metros; no crear growth_history sin medición fechada |
| frecuenciaRiegoDias | watering_frequency_days | Entero 1–36500; textos ambiguos no se interpretan |
| ultimoRiego | baseline_last_watered_at inicialmente | No crear evento; baseline_source=legacy_snapshot |
| WateringEvent.id | watering_events.id | Mismo UUID |
| plantId | plant_ref_id; plant_id solo si existe planta completa propia | Crear historical_only si falta, no planta ficticia |
| plantName | plant_name_snapshot | Nombre del evento; no sustituir por nombre actual |
| occurredAt | occurred_at | UTC si llevaba offset; revisar si el raw antiguo no lo llevaba |
| type=manual_registration | event_type=manual | Solo equivalencia declarada; jamás orden de hardware |
| schemaVersion=1 | metadata fuente, no protocol_version | Versiones distintas |

No hay jardines, species_id ni mediciones de crecimiento en los modelos Flutter
actuales. Al descargar estos datos el DTO y SQLite deben conservarlos íntegros,
aunque Tree todavía no los exponga. PATCH solo envía campos realmente editados.
No serializar Tree como sustituto completo de una imagen de servidor.

Tree valida ID no vacío, NO UUID; también acepta nombres/especies sin máximos de
API. Conserva fechas sin offset con DateTime.parse y no tiene límite futuro. Estas
incompatibilidades deben detectarse en raw_json antes de llamar fromJson: ese
método puede recortar texto, asignar IDs o interpretar zona local.

### IDs y fechas problemáticos

- UUID válido con otra representación: equivalencia registrada en mapping_json,
  canonicalizar sin cambiar identidad. No regenerar UUID válido por colisión o
  porque el nombre cambió.
- ID ausente en formato antiguo: asignar una vez y guardar el mapa durable ANTES
  de publicar datos. No recrearlo por cada reintento de migración.
- ID presente pero no UUID o duplicado: recovery/confirmación explícita. Cualquier
  remapeo incluye referencias de eventos y avisos, conserva el identificador crudo
  y el mapa original→nuevo. Nunca sobrescribir una de dos filas duplicadas.
- Fecha sin offset: conservar cadena original y zona/resolución separadas. Si se
  asume la zona actual del teléfono, la persona debe confirmar esa hipótesis; el
  viaje o cambio de horario puede hacerla errónea. Horas ambiguas/inexistentes
  requieren elección explícita; no normalizarlas silenciosamente.
- El formulario de registro actual asigna ultimoRiego=DateTime.now() sin evento.
  El snapshot no guarda esa procedencia: NO inferir legacy_registration por nombre
  o igualdad de horas. Usar legacy_snapshot, conservar valor y no afirmar un riego
  manual real. Para registros nuevos puede registrarse declared_initial explícito.
- Nombre/especie largos, JSON incompatible, número inválido o fecha futura: dejar
  original recuperable. Edición correctiva requiere confirmación y traza; no
  truncamiento, valor cero, fecha de recepción como sustituto ni descarte.
- Planta de ejemplo: el legado no tiene indicador demo. No decidir por el nombre.
  Toda planta existente participa en la vista de selección voluntaria. Solo una
  nueva planta conocida del flujo de ejemplo puede llevar origin=demo.

## 5. Migración reanudable SharedPreferences → SQLite

Estados: captured → mapped → staged → verified → active; cualquier error pasa a
blocked conservando diagnóstico y respaldo. El marcador AUTORITATIVO de active
vive en SQLite, no repartido entre SQLite y preferencias.

1. Adquirir exclusión de escritor para impedir cambios mientras se toma la fuente.
   Leer directamente TreePreferencesStore.read/reload, NO loadSnapshot: el loader
   actual puede actualizar el legado y escribir IDs. No tocar la clave trees.
2. Capturar un envelope con key_present y la lista ORIGINAL de strings en orden.
   Guardar UTF-8 íntegro y hash en recovery_backups, confirmar transacción y verificar
   lectura+hash. Es respaldo del valor lógico, no copia byte a byte del XML Android.
3. Registrar migration_run único por backup/hash y versión. Parsear sin destruir
   originales; legacy_records conserva cada elemento. La ausencia de key y una
   lista vacía son estados distintos. Snapshot inválido nunca se convierte en vacío.
4. Confirmar mapas de IDs asignados y resoluciones explícitas de fechas. No se
   regeneran cuando se repite el mismo backup/run. Dependencias se resuelven antes
   de insertar eventos; no crear eventos a partir de ultimoRiego.
5. Poblar tablas candidatas dentro de una transacción: espacio anónimo, referencias,
   plantas, eventos y comandos local_only. Usar run/IDs para detectar un reintento,
   no INSERT OR REPLACE sobre datos ya editados. No escribir preferencias en paralelo.
6. Verificar conteos y equivalencia de campos/IDs/referencias, hashes originales,
   foreign_key_check e integrity_check. Debe poder reconstruirse el snapshot semántico
   original, incluidas filas incompatibles en recovery. Si hay incompatibilidades
   sin resolver, NO activar parcialmente ni ocultar filas: pantalla de recuperación
   o lectura del origen; fuente previa conserva autoridad y no se sube nada.
7. Confirmar verificación y active_storage=sqlite_v1 en LA MISMA transacción que
   habilita el nuevo repositorio. Nunca basarse solo en un bool de preferencias.
   Después, todas las escrituras van únicamente a SQLite. El repositorio anterior
   queda deshabilitado y no se ejecuta su inicialización automática sobre un error.
8. Reiniciar y verificar lectura SQLite, recuentos y respaldo recuperable. Conservar
   clave original y backup; limpieza futura exige autorización específica. No usar
   el respaldo como una segunda fuente editable después de activar SQLite.

Si se necesita continuar usando el almacenamiento anterior tras una migración
fallida, invalidar el candidato no activo y capturar un NUEVO backup al cambiar la
fuente. No aplicar un viejo candidato a una fuente ya modificada. Después de active,
no hacer rollback de app hacia el JSON antiguo: perdería ediciones nuevas; recuperar
SQLite y sus comandos, o exportar explícitamente con un procedimiento aprobado.

Si faltaba la clave, marcar never_initialized y delegar al flujo de primera apertura
sin inventar una migración de plantas que no existían. La decisión de mantener la
planta inicial de ejemplo se registra aparte; si se conserva, crearla exactamente
una vez como dato local/demo no subido. Una fuente vacía explícita permanece vacía.

Pruebas de corte deben cubrir cada COMMIT anterior, espacio insuficiente, reinicio,
lectura corrupta y activación. No afirmar que un try/catch equivale a durabilidad
frente a cierre forzado o corte eléctrico. Las pruebas instrumentadas en Android
son un criterio de aceptación, no algo verificado por esta entrega documental.

## Fuentes verificadas

- [sqflite](https://pub.dev/packages/sqflite): plataformas y transacciones.
- [sqflite_common_ffi](https://pub.dev/packages/sqflite_common_ffi): escritorio y requisitos nativos.
- [sqflite_common_ffi_web](https://pub.dev/packages/sqflite_common_ffi_web): experimental, IndexedDB y workers.
- [SQLite atomic commit](https://www.sqlite.org/atomiccommit.html).
- [SQLite PRAGMA](https://www.sqlite.org/pragma.html#pragma_synchronous).
