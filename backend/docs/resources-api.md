# E.4 — contrato REST implementado, en revisión

Código y pruebas aisladas; **no aplicado ni desplegado en desarrollo**.
Sustituye deliberadamente el contrato escritor 3.2D. Las rutas mantienen Bearer
access token y contexto owner autenticado por transacción. Auth conserva su contrato.

## Rutas, headers y respuestas

| Escritura | Headers obligatorios | Respuesta inicial y replay |
| --- | --- | --- |
| POST /api/v1/gardens | Idempotency-Key UUID | 201 GardenRead, Location individual, ETag r1 |
| PATCH /api/v1/gardens/{id} | Key + If-Match | 200 GardenRead/ETag |
| DELETE /api/v1/gardens/{id} | Key + If-Match | 204 vacío/ETag tombstone |
| POST /api/v1/plants | Key | 201 PlantRead, Location individual, ETag r1 |
| PATCH /api/v1/plants/{id} | Key + If-Match | 200 PlantRead/ETag |
| DELETE /api/v1/plants/{id} | Key + If-Match | 204 vacío/ETag tombstone |
| POST /api/v1/plants/{id}/growth-history | Key | 201 GrowthRead, Location /api/v1/growth-history/{id}, ETag r1 |
| POST /api/v1/plants/{id}/watering-events | Key | 201 WateringRead, Location /api/v1/watering-events/{id}, ETag r1 |

Key significa Idempotency-Key: una UUID, sin headers repetidos; namespace global
por owner entre acciones/recursos y futuro sync. If-Match es un único ETag fuerte
`"bf1-<tipo>-<uuid>-r<revision>"`; tipos garden, plant, growth, watering. PATCH/DELETE
requieren tipo/UUID del objetivo, sin W/, listas o *. POST rechaza If-Match.

revision es string decimal positiva, sin signo/ceros iniciales, máximo BIGINT
9223372036854775807. Hechos tienen "1". GET individual y respuesta escritora usan
los mismos bytes UTF-8/ETag; no se unen campos mutables de otras entidades.
Cambiar jardín o catálogo no cambia la representación de una planta; renombrar
la planta no cambia el snapshot histórico del hecho. GET activo de un tombstone
retorna 404. Listas de jardines/plantas admiten include_deleted=true.

Replay se reconoce después de autenticar y antes de CAS/relaciones/reloj. Devuelve
status, bytes de cuerpo, Content-Type, Location y ETag originales, incluso tras
edición/borrado. Los demás headers de transporte no son parte del recibo.
Una Key distinta con UUID propio de jardín/planta existente no fusiona creaciones.
Un hecho con UUID propio y campos declarados idénticos reconoce el hecho original,
sin grupo/revisión nuevos; contenido distinto es conflicto. REST nuevo exige planta
activa para una Key nueva; el replay funciona después de borrado.

No-op con revisión vigente devuelve representación/ETag sin incrementos ni grupo;
tiene recibo. Borrado repetido con Key nueva exige revisión vigente del tombstone.
Jardín se archiva conservando todas las asignaciones, incluidas plantas eliminadas;
no permite asignaciones nuevas. Perfil de una planta ya asignada puede editarse
conservando ese jardín archivado. Historial sigue consultable tras borrar planta.

## Entradas y representaciones

- Jardín: name obligatorio, trim/no vacío/200; description nullable/4000. PATCH
  admite esos dos campos, name no null. Respuesta añade revision/updated_at/deleted_at.
- Planta: name y watering_frequency_days (int estricto 1–36500) obligatorios.
  Opcionales garden_id, species_id, species_label (250), initial_height_m positiva
  finita, last_watered_at inicial. PATCH no admite last_watered_at. Baseline inicial
  se conserva sin fabricar riegos. Catálogo no sobrescribe especie libre o frecuencia.
- Crecimiento: measured_at, al menos altura/diámetro positivo finito en metros;
  diameter_kind stem/canopy requerido junto a diámetro; notes nullable/4000.
- Riego: occurred_at; tipo manual servidor. Sin litros, bombas o confirmación física.
- UUID opcional solo en creación, no null explícito: generado **después** de lookup
  si fue omitido. owner/revision/created_at/recorded_at/snapshot y otros internos
  no son entrada. Los hechos añaden revision "1" a la respuesta.
- RFC3339 con zona y hasta seis decimales, normalizado UTC microsegundos. El reloj
  servidor se evalúa tras lookup; una fecha futura se rechaza durablemente.
  Dimensiones son binary64 finitas; enteros que pierdan precisión al convertir se
  rechazan. No normalización Unicode NFC/NFD ni corrección de fechas silenciosa.

PATCH vacío y null de obligatorio se rechazan. Omisión no equivale a null en la
huella: PATCH omitido conserva, null limpia nullable. Rechazar claves extra o
repetidas, surrogates aislados y NUL (no representable en PostgreSQL text).
Cuerpo y operación canónica <=65536 bytes, profundidad <=16 antes del parser;
streaming no elude el límite. Grupo indivisible <=4 entidades y 65536 bytes.
JCS solo canonicaliza la intención interna rest-v1; el recibo conserva los bytes
REST generados por SQL. No se modifica el hash/envelope sync ni el JSON E.3.

GETs conservan jardines, plantas, especies, growth-history y watering-events,
incluidos listados globales y por planta. `{items,total,limit,offset}`: default20,
máximo100, offset0..1000000; orden created_at/id y fechas históricas descendentes.
Paginación de UI, sin cursor/feed HTTP ni ETag de colección o If-None-Match/304.
Especies solo lectura; vacío permitido. No PUT ni edición/borrado de hechos.

## Errores y confirmación

- Sin recibo: 401/403, 422 estructural (incluida Key ausente/inválida), 428 sin
  If-Match, 413 límite, 415 medio, fallos DB/5xx. No detalles SQL/inputs secretos.
- Durables: 404 resource_not_found para ausente/ajeno sin estado; 412
  revision_conflict propio; 409 entity_exists, identity_unavailable,
  entity_content_mismatch, garden_archived; 422 timestamp_in_future con server_time.
- Key usada para otra intención: 409 operation_id_reused sin reemplazar el recibo.
  Corregir un rechazo terminal requiere Key nueva; repetir la misma conserva error.
- Error inesperado revierte datos, contador, grupo y recibo. Deadlock/serialización
  permiten hasta tres intentos internos con los mismos bytes/ID; agotamiento 503.
  Respuesta perdida tras COMMIT se recupera con replay, sin otra operación.

Recursos privados: no-store/no-cache. Datos, grupos y recibos se confirman antes
de emitir respuesta HTTP; sin HTTPException que revierta un rechazo durable.

## Persistencia y permisos

Solo resource_apply(uuid,text) escribe; repositorios Python hacen SELECT. Rol API
sin INSERT/UPDATE/DELETE ni permisos de columna de 0003; sin acceso directo a tablas
privadas. FORCE RLS, owner derivado de auth_access y relaciones compuestas intactos.
owner_id GUC depende de proceso/conexión confiable, no es prueba contra credenciales
runtime comprometidas. La guardia de arranque/petición verifica head y capacidades,
sin migrar automáticamente ni recurrir al escritor anterior.

Ver [diseño aprobado](sync/e4a-contract-gateway-migration.md),
[resultados](sync/e4-validation-results.md) y [migración y límites](sync/e4-deployment.md).
