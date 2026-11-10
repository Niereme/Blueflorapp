> **Cierre autorizado de 3.2E.4 — 2026-11-10.** Hito Git v0.3.5;
> creación de commit y publicación en origin/main autorizadas, publicación pendiente
> de comprobación. Se conservan las limitaciones documentadas. E.5 no iniciada ni
> autorizada. Los estados de preparación anteriores quedan como trazabilidad.

> **Estado vigente al preparar cierre (2026-11-10):** implementación y validación
> técnica E.4 completadas; cierre autorizado, publicación Git pendiente. Suite aislada anterior: 292 aprobadas.
> Respaldo/restauración del origen vacío acreditados y CHECK resuelto por las dos
> variantes exactas; desarrollo migrado a 0005, validado READ ONLY y lifespan/liveness.
> Sin CRUD HTTP en desarrollo ni servicio persistente. E.5 no iniciada ni autorizada.
> Véanse [migración real](e4-development-migration-results.md) y
> [compatibilidad](e4-check-compatibility-results.md).
> El cuerpo conserva la secuencia histórica de propuestas, fallos y resoluciones;
> sus autorizaciones pendientes o estados antiguos no sustituyen este estado vigente.
> Los comandos históricos no son instrucciones para repetir operaciones.

# BlueFlora — E.4A: contrato, gateway y migración propuestos

**Diseño aprobado para implementar y probar en esquemas aislados.** Estado: 2026-11-09.
La implementación E.4 está en revisión; desarrollo y despliegue siguen pendientes.
El cuerpo conserva la propuesta E.4A de referencia. Véanse
[evidencia E.4](e4-validation-results.md) y [corte pendiente](e4-deployment.md).
Base: `af2bd84dadae3fba8a8fd8119c54a2307520cfa9`, cierre publicado de E.3.
La aprobación conceptual cubre servidor, ocho escritores REST, CAS, recibos y
feed transaccionales. Este documento precisa decisiones para una autorización
posterior; no autoriza código, SQL, permisos, dependencias ni despliegue.

## 1. Base comprobada y alcance

Fuentes: `app/modules/{common,gardens,plants,watering}`, `app/db/connection.py`,
`migrations/versions/0001_initial.py`–`0003_resource_permissions.py`,
`migrations/env.py`, `pyproject.toml`, contratos REST/autenticación y documentos E.1.
GrowthService está en `modules/plants/service.py`, no en un módulo growth separado.
Los ocho escritores son altas/ediciones/borrados de jardines y plantas, alta de
medición y alta de riego. Autenticación mantiene sus funciones y transacciones;
el catálogo es de lectura. No se crea un feed de sesiones o credenciales.

Hoy ResourceRepository autentica con auth_access, establece contexto y abre una
transacción; los servicios Python deciden relaciones, borrado y proyección de
riego. El rol API tiene DML directo explícito en 0003, incluidos UPDATE de columnas.
Solo plants tiene revision (INTEGER), updated_at y deleted_at. No existen CAS,
ledger ni feed. El riego busca duplicados después de exigir planta activa; esa
secuencia no permite replay tras borrado. HTTPException dentro de la transacción
la revierte: no sirve para confirmar un rechazo durable.

E.3 sí tiene SQLite v2/outbox anónimo Android: no es un envelope sync, su JSON
ordenado no es JCS y las capturas previas quedan fuera de la cola. No se toca
Flutter ni se atribuyen cuentas o HTTP a esa entrega.

Discrepancias documentales: el README E.1 describe SharedPreferences y ausencia de
cola como fotografía anterior a E.3; la transición aún dice cierre Git pendiente y
E.4 no autorizada. El usuario confirmó cierre/publicación E.3 y autoriza únicamente
esta preparación E.4A. No se reescriben esas fotografías ni los contratos E.1 en
esta entrega. Al autorizar implementación habrá que actualizar sus estados y el
contrato REST conjuntamente, sin declarar implementado el esquema objetivo entero.

## 2. Arquitectura recomendada

| Alternativa | Ventaja con el código actual | Coste y frontera privilegiada |
| --- | --- | --- |
| A: una función SQL para ocho acciones | Una única entrada puede impedir toda escritura parcial y retirar el DML runtime | Traslada reglas Python a PL/pgSQL; requiere pruebas de contrato y revisar una función mayor |
| B: Python orquesta funciones SQL menores | Conserva más reglas en los servicios actuales y divide funciones | Si cada helper puede escribir datos, recibos o grupos por separado, runtime puede omitir pasos. Exigir finalización mediante triggers diferidos y capacidades verificables añade un segundo protocolo; un GUC de «operación completa» falsificable no lo resuelve |

Recomendar **A** para este tamaño de dominio. No basta envolver los repositorios
actuales y mantener sus permisos. Una función privilegiada pública a runtime:
`S.resource_apply(p_operation_id uuid, p_request_canonical text) RETURNS jsonb`.
Sin defaults, sobrecargas, owner como parámetro, SQL dinámico ni argumentos para
inyectar respuestas, revisiones o grupos arbitrarios. Lista cerrada de ocho acciones.
S representa el esquema validado del destino, nunca un identificador del cliente.
No se implementa esta firma en E.4A.

| Capa | Responsabilidad final propuesta |
| --- | --- |
| Router | Extraer token, headers y ruta; rechazar estructura inválida; emitir el status, bytes de cuerpo y headers de negocio devueltos después de COMMIT. No volver a serializar el replay con un DTO que altere su cuerpo |
| Servicio Python común | Adaptar REST a intención rest-v1; normalizar sintaxis y tipos, conservar presencia de campos; JCS y bytes congelados. Mapear resultados durables, sin decidir relaciones o CAS mediante consultas previas |
| Repositorio | Una conexión/transacción; verificar rol y sesión como hoy, fijar owner local, invocar el gateway una vez. Confirmar antes de devolver. Reintentar solo fallos transitorios admitidos con los mismos bytes/ID |
| Gateway SQL | Validar contrato interno cerrado y límites; bloquear, reconocer replay, decidir relaciones/CAS/reglas de estado, generar valores, aplicar datos y proyecciones, formar imágenes/respuesta, guardar recibo y grupo atómicos |
| Lecturas | Mantener repositorios SELECT bajo RLS; adaptar DTO/ETag y filtros de archivado. Ningún SELECT de servicio autoriza una escritura posterior |

Se trasladan desde los servicios: existencia/propiedad/estado de relaciones,
archivado, preservación de vínculos, CAS, no-op, unicidad semántica de hechos,
comparación con hora servidor, snapshot del nombre, baseline y max de riegos,
incrementos y tombstones. Los DTO conservan validación estructural pura: claves,
tipos, nulabilidad, rangos estáticos y dimensiones emparejadas. La función debe
volver a comprobar esas condiciones para resistir llamadas directas runtime;
no debe existir una segunda decisión semántica Python basada en estado/tiempo.
Vectores compartidos verifican que el adaptador y el contrato SQL aceptan los
mismos valores; constantes de contrato documentadas, sin dos algoritmos de dominio.
El validador Measured.not_future debe dejar de ejecutarse antes del ledger.
La generación default_factory de UUID tampoco debe congelar un UUID distinto
antes de consultar el recibo.

## 3. Identidad y privilegios propuestos

Flujo existente conservado: token opaco → digest → auth_access dentro de la
transacción → user_id autenticado → set_config('blueflora.owner_id', UUID, true)
→ gateway en esa misma conexión. Nunca usar owner enviado por HTTP; contexto
transaccional, no global. Sin contexto válido se rechaza antes de escribir.

RLS protege consultas sin filtro y relaciones entre propietarios; no autentica
al titular de una conexión. **El rol runtime puede establecer este GUC**: una
conexión comprometida puede simular otro owner e invocar el gateway. La confianza
incluye proceso API y sus credenciales. Quitar DML impide eludir el protocolo,
pero no convierte el GUC en identidad infalsificable. Endurecer esta frontera
exigiría otro diseño de autenticación SQL, fuera de E.4.

M = propietario/migrador existente (`blueflora_dev` o `blueflora_test`), R = rol
API correspondiente (`blueflora_api` o `blueflora_api_test`). No crear roles ni
membresías. Preflight deberá confirmar propietarios reales; no asumirlos de datos
consultados hoy. M posee tablas nuevas y función. Mantener M y R sin superuser ni
BYPASSRLS. SECURITY DEFINER ejecuta como M, pero FORCE RLS también sujeta a M a
las políticas: no da acceso global automático. Las políticas owner_isolation de
recursos son aplicables a M; no habilitar auth_internal en el gateway.

Cada tabla nueva privada usa ENABLE y FORCE RLS, con USING **y** WITH CHECK:
`owner_id = nullif(current_setting('blueflora.owner_id', true), '')::uuid`.
Conservar políticas existentes. Las políticas auth_internal de 0002 son para M,
y en users solo SELECT/INSERT; no se amplían a recibos ni recursos. Para enumerar
usuarios en backfill, M puede usar ese contexto existente únicamente durante el
SELECT de IDs, guardándolo/restaurándolo incluso ante error; luego backfill por
owner con contexto local normal, sin desactivar RLS. No conceder ese acceso a R.

### Matriz final y delta exacto a someter a aprobación

| Objeto | R final | M / PUBLIC |
| --- | --- | --- |
| Esquema S | USAGE existente, sin CREATE | M conserva propiedad/capacidad de migrar; ningún nuevo GRANT a PUBLIC. Comprobar CREATE efectivo heredado de PUBLIC: si existe, bloquear despliegue y pedir corrección específica |
| users | SELECT(id,email,is_active,created_at), como 0002 | RLS y funciones auth actuales sin cambios; no acceso a password_hash |
| species | SELECT | Sin escritura API; sin nuevos permisos |
| gardens, plants, growth_history, watering_events | Solo SELECT | M propietario bajo FORCE RLS; retirar todas las escrituras de R indicadas debajo |
| plant_identities, sync_owner_state, sync_operations, sync_change_groups | Ningún privilegio directo, ni SELECT | M propietario bajo FORCE RLS; REVOKE ALL a PUBLIC y R sobre cada tabla explícita |
| resource_apply(uuid,text) | EXECUTE solamente | Propietario M; SECURITY DEFINER, LANGUAGE plpgsql, SET search_path = pg_catalog, pg_temp; REVOKE ALL a PUBLIC, GRANT EXECUTE a R |
| reject_immutable() RETURNS trigger | Ningún EXECUTE directo | Propietario M; SECURITY INVOKER, search_path seguro; REVOKE ALL a PUBLIC y R; enlazar únicamente triggers de tablas explícitas |
| Siete funciones auth existentes | EXECUTE ya concedido | Conservar firmas, propietarios, ACL y search_path; sin nuevas funciones auth |

Retiradas exactas respecto de 0003 (notación documental, no script ejecutado):

- REVOKE INSERT, DELETE ON S.gardens FROM R.
- REVOKE UPDATE(name,description) ON S.gardens FROM R.
- REVOKE INSERT ON S.plants FROM R.
- REVOKE UPDATE(garden_id,species_id,name,species_label,initial_height_m,
  watering_frequency_days,last_watered_at,revision,deleted_at,updated_at)
  ON S.plants FROM R.
- REVOKE INSERT ON S.growth_history FROM R; igual para S.watering_events.
- Verificar ausencia de permisos de tabla UPDATE/DELETE adicionales y de GRANT
  OPTION, TRUNCATE, REFERENCES, TRIGGER y permisos de columna heredados o de
  PUBLIC. Si aparecen permisos no descritos por 0001–0003, detener y revisar el
  delta; no retirarlos silenciosamente ni aplicar REVOKE global sobre el esquema.

Revocar UPDATE de tabla no elimina UPDATE de columna. Ninguna columna nueva se
concede a R. No GRANT ALL, ALL TABLES, secuencias, roles, default privileges ni DDL
runtime. Crear función y retirar EXECUTE predeterminado PUBLIC en la misma
transacción, antes de publicar el esquema. Todas sus referencias cualificadas;
pg_temp al final, sin nombres de objetos/políticas controlados por el cliente.
Referencia de semántica FORCE RLS:
[PostgreSQL, políticas de filas](https://www.postgresql.org/docs/18/ddl-rowsecurity.html).
Las siete firmas existentes preservadas son auth_lookup(text),
auth_register(uuid,text,text), auth_start_session(uuid,uuid,text,text),
auth_access(text), auth_rotate(text,text,text), auth_logout(text), auth_attempt(text).

Triggers BEFORE UPDATE OR DELETE rechazan modificación de sync_operations,
sync_change_groups y hechos growth_history/watering_events. Sin TRUNCATE runtime.
La función solo INSERTa recibos/grupos finales; no expone begin/finish ni setters.
M puede alterar DDL por ser migrador: no se promete inmutabilidad contra el
administrador. Sin purga ni compactación en E.4.

## 4. Contrato REST propuesto, pendiente de aprobación

### Reglas comunes

`Idempotency-Key` obligatorio en las ocho mutaciones: un UUID, normalizado a
minúsculas, sin listas ni headers repetidos; ausente o inválido produce 422 no durable.
Namespace único **(owner_id,
operation_id)** para todos los recursos y transportes REST/sync futuros; no se
reutiliza una clave en otra ruta/acción. No crear sesiones móviles para obtenerlo.
Cada recurso mutable usa BIGINT positivo 1..9223372036854775807; HTTP revision
es **cadena decimal canónica**, sin signo ni ceros iniciales. Hechos inmutables
exponen revision "1". Esto cambia PlantRead.revision de número a cadena.

ETag fuerte de representación individual:
`"bf1-<tipo>-<uuid>-r<revision>"`, tipo garden, plant, growth o watering; UUID
canónico. GET individual y respuestas exitosas con entidad lo incluyen. PATCH y
DELETE solo aceptan un If-Match fuerte de ese formato para el mismo tipo/ID;
no listas, W/ ni *. Ausencia: 428; sintaxis/tipo/ID incorrecto: 422. ETag con
revisión válida distinta de la propia actual: 412 durable. GET de listas conserva
paginación de UI, sin ETag de colección ni cursor incremental. No implementar
If-None-Match/304 en esta entrega. Catálogo mantiene contrato actual.

| Operación / acción | Headers y revisión base | Primera respuesta / replay | Estado eliminado, ajeno y no-op |
| --- | --- | --- | --- |
| POST /gardens — garden.create | Key; sin If-Match, base null | 201 + cuerpo GardenRead, Location /api/v1/gardens/{id}, ETag r1; replay idéntico | ID propio existente: 409 entity_exists; ID ocupado ajeno: 409 identity_unavailable genérico; no actualiza por coincidencia |
| PATCH /gardens/{id} — garden.update | Key + If-Match | 200 + entidad/ETag; sin Location; replay idéntico | Ausente/ajeno/archivado: 404 genérico; mismos valores con base vigente: 200 sin incremento ni grupo |
| DELETE /gardens/{id} — garden.delete | Key + If-Match | 204 cuerpo vacío + ETag tombstone; sin Location; replay idéntico | Archiva aunque tenga plantas; conserva asignaciones; ya archivado y base vigente: 204 sin incremento/grupo; base vieja: 412; ausente/ajeno: 404 |
| POST /plants — plant.create | Key; sin If-Match, base null | 201 + PlantRead, Location /api/v1/plants/{id}, ETag r1; replay idéntico | Conflictos de ID como jardín; jardín archivado: 409 garden_archived; relación ausente/ajena: 404 genérico |
| PATCH /plants/{id} — plant.update | Key + If-Match | 200 + entidad/ETag; sin Location; replay idéntico | Eliminada/ausente/ajena: 404; valores iguales y base vigente: sin revisión/grupo. Conservar jardín ya archivado permitido; nueva asignación a él: 409 |
| DELETE /plants/{id} — plant.delete | Key + If-Match | 204 vacío + ETag tombstone; sin Location; replay idéntico | Conserva planta, identidad e historial; ya eliminada con base vigente: no-op; base vieja: 412; ausente/ajena: 404 |
| POST /plants/{id}/growth-history — growth_measurement.create | Key; sin If-Match, base null del hecho | 201 + GrowthRead, Location /api/v1/growth-history/{fact_id}, ETag r1; replay idéntico | Nueva operación exige planta activa; eliminada/ausente/ajena: 404. UUID de hecho propio idéntico: 201 con hecho original, sin grupo; distinto: 409 entity_content_mismatch; ajeno: identity_unavailable |
| POST /plants/{id}/watering-events — watering_event.create | Key; sin If-Match, base null del hecho | 201 + WateringRead, Location /api/v1/watering-events/{fact_id}, ETag r1; replay idéntico | Mismas reglas de hecho; evento antiguo se inserta, no retrocede last_watered_at ni incrementa revisión de planta si no cambia su proyección |

POST con If-Match se rechaza 422 estructural; no ignorarlo. Todos los casos de
la tabla heredan el tratamiento común de errores de abajo. GET de plantas/jardines
activos excluye tombstones; listas permiten include_deleted con el mismo criterio
que plantas actual. Historial sigue accesible para plantas borradas y conserva
plant_ref_id y plant_name_snapshot. No se expone una planta ficticia para una
identidad historical_only. REST nuevo no admite insertar hechos en eliminadas;
el soporte sync histórico futuro se mantiene separado.

En hechos, mismo UUID con otra Key solo es no-op si coincide referencia, instante
y campos declarados normalizados (incluidas notas/dimensiones). Nombre histórico
y recorded_at generados se toman del hecho original, no del nombre actual. No se
reescribe el snapshot tras renombrar. Para una operación nueva se exige planta
activa antes de deduplicar hechos; el **replay por Key** tiene prioridad sobre esa
comprobación y funciona tras borrado. No prometer que dos envelopes con distinto
snapshot declarado en sync sean la misma intención REST.

### Recibos, errores y reproducción

1. Autenticar siempre, incluso para replay. Validar estructura inmutable de la
   petición; después, dentro de la transacción, bloquear owner y buscar recibo
   **antes de CAS, existencia actual, reloj y relaciones**. Si coincide intención,
   devolver status, cuerpo serializado, Location y ETag originales. No sustituir
   la respuesta original por la entidad vigente: puede haberse editado o borrado.
2. Misma Key con otra intención: 409 operation_id_reused, sin cambiar el recibo
   original, ni insertar otro, ni consumir grupo. Comparar bytes canónicos además
   del hash. Una corrección tras conflicto/rechazo terminal requiere **nueva Key**;
   repetir exactamente la anterior conserva su rechazo, aunque cambie el estado.
3. Estructurales/no durables: 401/403 de autenticación/autorización, 428 por falta
   de If-Match, 422 por headers, tipos, campos desconocidos, JSON duplicado,
   nulabilidad o rangos estáticos inválidos; 413 por límite, 415 por medio no
   admitido. No recibo ni cambios. PATCH vacío sigue 422. Fallos 5xx/DB y abortos
   de transacción no producen recibo. No se añade rate limiting en E.4.
4. Tras estructura y lookup: 404 de objetivo/relación ausente o ajena (sin estado
   ajeno), 412 de CAS propio, 409 de identidad/estado/archivo/datos distintos y
   422 timestamp_in_future por fecha futura son terminales durables (incluye
   server_time original en el recibo). Guardar error
   genérico `{ "detail": { "code": "...", "message": "..." } }`, sin SQL,
   constraints ni UUID de terceros. Para ocultar existencia, ausencia/propiedad
   se comprueba antes de comparar revisión del objetivo. Un UUID ajeno ocupado
   solo genera identity_unavailable sin propietario o representación.
5. Recibos applied/conflict/rejected son finales; errores no durables no se guardan
   como rejected. Sin mutación no hay secuencia ni grupo vacío. blocked es concepto
   de dependencias sync futuro, no un resultado REST a implementar ahora.
6. Guardar bytes UTF-8 del cuerpo, status, Content-Type y presencia/valor exactos
   de Location/ETag; DELETE 204 usa cero bytes. Respuestas de error no llevan
   Location ni ETag. Date, identificador de petición y cabeceras de transporte no
   forman parte del recibo; conservar Cache-Control privado/no-store actual.
   No lanzar HTTPException terminal dentro del context manager: confirmar primero
   y después emitir respuesta. Si falla COMMIT no enviar un resultado confirmado.

Omisión conserva su significado: PATCH omitido no cambia; null solo limpia campos
nullable. En POST, omisión aplica default después de lookup; null no equivale a
omisión en la huella, aunque ambos terminen en el mismo valor permitido. No aceptar
owner/revision/recorded_at/snapshot internos. Mantener extra=forbid y detectar
claves duplicadas antes de Pydantic; no descartar silenciosamente campos futuros.
UUID omitido en POST conserva esa omisión: generar solo en la primera ejecución,
guardarlo en respuesta/recibo. null para id se rechaza. Límites propuestos: cuerpo
REST y operación canónica <=64 KiB, profundidad <=16; imagen/grupo <=64 KiB y
hasta cuatro entidades, comprobados antes de cualquier confirmación.

**Cambios incompatibles con 3.2D:** headers obligatorios, revisión string/BIGINT,
ETag/Location y revision de hechos/nuevos campos de jardín; DELETE jardín de
borrado físico/409 con plantas a archivado/204; PATCH no-op ya no incrementa;
DELETE repetido requiere precondición o replay; semántica durable de rechazos y
fecha futura tras ledger; límites de tamaño/duplicados más estrictos. No se
mantiene una ruta de compatibilidad que escriba sin CAS/ledger/feed. Requieren
aprobación explícita y actualización de OpenAPI/resources-api al implementar.

## 5. Canonicalización y dependencia candidata

REST no tiene que enviar un envelope JCS por red. Se recomienda **JCS también
para la intención interna REST**, con versión propia rest-v1, en lugar de mantener
otro algoritmo. Propuesta de envelope cerrado: format, operation_id, action,
target (UUID de ruta o null), if_match (ETag normalizado o null), payload (solo
campos presentes). Método/ruta se derivan inequívocamente de action/target; no
incluir query arbitraria. POST usa payload.id solo si vino declarado; defaults,
UUID/fechas servidor, estado actual y snapshot generado se excluyen de intención.
No aceptar este envelope interno como un nuevo endpoint HTTP. La función exige
que operation_id del envelope coincida con p_operation_id; action/target y
If-Match deben ser coherentes con la variante permitida, sin campos extra.

Python convierte UUID a minúsculas, fechas a UTC RFC3339 con seis decimales y Z,
revisiones a cadenas decimales, nombre con el trim ya contratado; conserva arrays,
null y presencia. No aplicar NFC/NFD ni case folding a textos. Decimal arbitrario
no se convierte silenciosamente a float; dimensiones siguen el dominio binary64
finito actual y enteros estrictos de frecuencia. Rechazar NaN, Infinity, overflow,
surrogates aislados, claves no string y duplicadas antes de perder información.
Revisiones BIGINT viajan como strings para evitar pérdida IEEE754.

Candidata: **rfc8785==0.1.4**, Apache-2.0, Python puro sin dependencias de ejecución;
Requires-Python >=3.8, compatible por metadatos con >=3.12 del proyecto. El entorno
3.14.4 deberá validarse con vectores antes de adoptarla: no se afirma prueba real.
Motivo: serializer RFC8785 dedicado que devuelve bytes UTF-8 y evita un JCS casero.
No se instala ni cambia pyproject en E.4A. Fuentes primarias consultadas:
[PyPI 0.1.4](https://pypi.org/project/rfc8785/0.1.4/) y
[repositorio/licencia](https://github.com/trailofbits/rfc8785.py).

El servidor Python canonicaliza y calcula SHA-256 de bytes JCS. El gateway recibe
el texto congelado, valida su estructura/tipos permitidos, calcula la huella de
esos mismos bytes UTF-8 y compara huella **y bytes** con el recibo. No acepta hash
ni respuesta dictados por el cliente. No recanonicaliza mediante jsonb::text.
La conformidad JCS de la entrada interna depende del adaptador de confianza;
la función aplica reglas de dominio incluso si runtime llama directamente.
Una entrada interna no canónica no debe poder convertir un replay diferente en
igual: la comparación exacta falla cerrada; no se promete validar JCS íntegro
mediante un segundo serializer SQL. Usar sha256 binario incorporado de PostgreSQL
sobre UTF-8, sujeto a comprobar versión disponible en preflight, sin pgcrypto nuevo.
El hash calculado Python y el SQL deben coincidir en los vectores de integración.

El protocolo sync mantiene su huella aprobada (protocol_version y seis campos de
operación); no cambiarla para parecerse a rest-v1. Namespace compartido significa
que una Key ya usada por REST queda reservada: reenviarla con envelope sync distinto
produce operation_id_reused. No hay equivalencia entre envelopes ni conversión
E.3→wire autorizada aquí; instalación/token/época no identifican la intención.

Pruebas normativas propuestas (no ejecutadas):

- [RFC8785 §3.2.2–3.2.4 y apéndice B](https://www.rfc-editor.org/rfc/rfc8785):
  valores binary64, cero negativo→0, exponentes, subnormales, extremos finitos,
  escape de controles y orden de propiedades por unidades UTF-16, no orden Python.
- Ejemplo local: `{"b":1.0,"a":null}` → bytes `{"a":null,"b":1}`;
  `{}` y `{"a":null}` distintos; 1, 1.0 y 1e0 iguales para campo numérico.
  Nombres con carácter suplementario frente a U+E000 deben ordenar según UTF-16.
- Corpus upstream y negativos I-JSON; NFC y NFD distintos; escape Unicode y
  carácter literal equivalentes si representan los mismos codepoints.
- UUID/offsets temporales equivalentes tras normalizar; revision "01" inválida;
  números enormes rechazados donde se requieren enteros exactos; boolean no es
  frecuencia. Generación de UUID/recorded_at no altera huella al repetir.
- Mismos bytes/huella Python/SQL, sin usar json.dumps(sort_keys=True) ni E.3.

## 6. Transacción, cambios y almacenamiento mínimo

Orden global: autenticar/contexto → crear perezosamente/bloquear fila owner_state
→ lookup recibo → jardines por UUID → identidades/plantas por UUID → hechos por
UUID → CAS/semántica → datos → contador → grupo → recibo → COMMIT. La autenticación
conserva el orden actual y no debe adquirir después bloqueos de recursos inversos.
Mover el bloqueo de jardín anterior al de planta en PATCH; ninguna ruta conserva
el orden inverso actual. Solo se consultan/bloquean relaciones del owner; species
es lectura compartida sin escritores de catálogo concurrentes autorizados.

Un owner queda serializado por esa fila hasta COMMIT; owners distintos avanzan
independientemente, salvo colisiones globales de UUID resueltas por constraints.
Incrementar un contador transaccional por grupo, no nextval/BIGSERIAL. Rollback
revierte contador/datos/grupo/recibo: no deja hueco de transacción abortada. Un
segundo escritor no obtiene N+1 antes de confirmar N. No usar hora de cliente,
updated_at o fecha de evento como cursor/ganador. Watering cambia hecho y planta
en un grupo si avanza proyección; evento antiguo solo incluye el hecho.

Fallos de negocio esperados no deben dejar una transacción SQL abortada: validar
antes o usar subtransacción para revertir **todos** los cambios tentativos antes
de insertar recibo terminal sin grupo. Constraint inesperada o error interno:
rollback total, 503 genérico, sin recibo. Deadlock 40P01/serialización 40001:
rollback completo, hasta tres intentos totales con mismos bytes/Key y autenticación
nueva por intento; agotamiento 503 sin afirmar que se aplicó. Si se perdió la
respuesta de COMMIT, reintentar con la Key consulta el ledger y evita duplicado.
Nunca reintentar un rechazo terminal como una intención nueva automáticamente.

| Objeto propuesto | Restricciones, índices y backfill mínimos |
| --- | --- |
| gardens | revision BIGINT NOT NULL CHECK >0, updated_at/deleted_at TIMESTAMPTZ; iniciar revisión 1, updated_at igual a created_at conocido, deleted_at null. Mantener UUID/campos y vínculos; no inventar cambios previos |
| plants | Convertir revision a BIGINT conservando valor; baseline_last_watered_at nullable y baseline_source; copiar last_watered_at existente como legacy_snapshot, o unknown si no existe. server_pre_sync es procedencia, no nuevo enum. No inventar eventos ni recalcular hacia atrás |
| plant_identities | id UUID PK global, owner_id FK users RESTRICT, UNIQUE(owner_id,id), state full/historical_only, revision BIGINT positiva. Una identidad por planta o referencia histórica; FK(owner_id,id) desde plants y FK(owner_id,plant_ref_id) desde cada historial |
| sync_owner_state | owner_id PK/FK users RESTRICT, epoch UUID NOT NULL, last_sequence BIGINT >=0. Crear con 0 para existentes y perezosamente para cuentas nuevas dentro de gateway; epoch estable, sin tocar auth_register |
| sync_operations | PK(owner_id,operation_id), FK owner a owner_state; format, canonical_request TEXT, fingerprint BYTEA de 32 bytes, action/entity, terminal_status CHECK applied/conflict/rejected, receipt JSONB, response_status/body BYTEA/content_type/location/etag, committed_sequence nullable y created_at servidor. Sin fila pending editable; índice PK satisface replay |
| sync_change_groups | PK(owner_id,epoch,sequence>0), change_id UUID, operation_id, images JSONB, count y tamaño UTF-8 comprobados <=4/64KiB; UNIQUE(owner_id,operation_id), UNIQUE(owner_id,change_id); FK(owner_id,operation_id) a operaciones, FK owner a state. Índice PK sirve lectura incremental futura |

La FK grupo→recibo debe ser DEFERRABLE INITIALLY DEFERRED si se inserta grupo antes
del recibo. Recibo con secuencia no null referencia (owner,epoch,sequence) del
grupo mediante FK diferida; añadir epoch nullable junto a secuencia y CHECK de
nulabilidad conjunta. Esto cierra la correspondencia sin confirmaciones parciales.
Recibos terminales sin cambio tienen ambos null. owner_state.epoch no se actualiza
por peticiones; recuperación de épocas requiere procedimiento administrativo
separado. No crear índices por timestamp para sustituir el índice incremental.
La revisión de identidad full acompaña a la revisión de planta en la misma
transacción; historical_only inicia en 1 y no inventa un estado de planta. La
identidad es soporte referencial interno, no una imagen adicional independiente
del recurso en el feed. Al agotar revisión o contador BIGINT, fallar cerrado
sin envolver el número ni confirmar datos parciales.
No generar grupos/operaciones históricos en backfill; estado previo será baseline
del bootstrap futuro, todavía no implementado.

Preservar UUID/fechas/plant_name_snapshot/plant_ref_id originales. Historial con
plant_id null puede referir una identidad historical_only sin crear plants.
plant_id no null debe corresponder a plant_ref_id y al mismo owner; CHECK local
más FK compuesta. Recomendación explícita a aprobar: cambiar FK histórica
ON DELETE SET NULL(plant_id) a RESTRICT para que una baja física administrativa
no reescriba hechos inmutables; runtime usa solo tombstone. Cambiar también
species→plants SET NULL a RESTRICT para impedir modificaciones de plantas fuera
del feed por borrado de catálogo. Esto no autoriza administración del catálogo.
No tocar las migraciones 0001–0003 ni borrar referencias para satisfacer nuevas FK.

No crear client_installations, bootstrap, imports o sesiones móviles. La instalación
origen del diseño E.1 queda nullable/ausente hasta su fase; source_kind=rest basta
ahora y no se inventa una instalación. Cualquier futura FK/grant es otra revisión.

## 7. Preflight y activación propuestos, no ejecutados

Preflight posterior con autorización específica, sin imprimir datos privados:

1. Confirmar base/roles/esquema/migraciones 0001–0003 reales y ausencia de escritores
   desconocidos. Revisar propietarios, FORCE/políticas, ACL efectivos de tabla,
   columna, función/esquema, membresías y PUBLIC; verificar sha256 disponible.
2. Detectar un UUID de identidad reclamado por distintos owners o por planta de
   otro owner; referencias huérfanas, owner inexistente, plant_id/ref incompatibles,
   duplicados y relación jardín/especie inválida. Historical_only lícito no es
   error; referencia contradictoria bloquea, sin reasignación automática.
3. Revisiones positivas dentro de BIGINT y margen de incremento; fechas válidas
   finitas y coherencia conocida, sin inventar zonas o corregir relojes. Preservar
   anomalías y solicitar resolución; no asumir que contenido histórico cumple
   los DTO actuales solo porque la columna admite ese dato.
4. Medir volumen, tamaño real UTF-8 de imágenes con envelope y grupos previstos,
   distribución por owner, duración/espacio para índices/backfill y bloqueo. Filas
   heredadas >64KiB bloquean hasta decidir solución: no truncar ni publicar grupos
   partidos. Confirmar respaldo coherente/recuperación y ventana antes del corte.
5. Ensayar primero en blueflora_test con datos sintéticos/aislados, no producción.
   Ninguna consulta o ensayo de esta lista se realizó en E.4A.

Despliegue conjunto recomendado:

1. Preparar código y migraciones sin activar rutas nuevas. Detener **todos** los
   escritores antiguos, drenar peticiones y pausar mantenimiento de catálogo y
   recursos; no hacer rolling deployment mezclando protocolos.
2. Upgrade 0004 (dominio/identidades/backfill/FK/RLS) y 0005 (estado/ledger/feed,
   gateway/triggers/ACL) bajo **una transacción externa** hasta el nuevo head.
   env.py ya usa engine.begin para la ejecución normal y exige transacción externa
   en esquemas de prueba; verificar que nuevas revisiones no introduzcan COMMIT,
   autocommit ni CREATE INDEX CONCURRENTLY. Validar FK antes de confirmar.
3. Publicar esquema, función y retirada de DML juntos; no ventana con escritores
   que puedan saltarse el protocolo. Arranque nuevo verifica head exacto y manifiesto
   de capacidades (columnas/tipos, firma, FORCE/ACL), no solo número de versión.
   Incompatibilidad impide readiness y operación de recursos; sin migración
   automática al arrancar ni fallback. Liveness puede seguir indicando proceso vivo.
4. Activar los ocho handlers y DTO nuevos en una única versión tras verificación.
   El binario anterior, aunque se inicie accidentalmente, falla al hacer DML por
   permisos; no sigue escribiendo sin ledger. No reactivar su servicio ni concederle
   permisos para «hacerlo funcionar». Comprobar contrato con pruebas autorizadas.

Si falla preflight, no migrar. Si falla backfill/FK/función/ACL antes de COMMIT,
rollback de toda la entrega y verificar que esquema/datos/grants anteriores
permanecen antes de reabrir el binario viejo. Si COMMIT es incierto, comprobar head,
capabilities y ledger antes de decidir; no repetir a ciegas downgrade/upgrade.
Si falla arranque tras COMMIT, mantener escrituras cerradas, conservar DB y corregir
hacia delante. Después de aceptar nuevas operaciones **no** downgrade destructivo,
restauración de copia anterior ni pérdida de ledger/feed/datos nuevos. Una reparación
debe preservar todas las operaciones confirmadas; desastre con pérdida de WAL/ACK
requiere reconciliación y nueva época/bootstrap futuro, no garantía de recuperación
inventada. No automatizar restauraciones ni regrants en el plan de despliegue.

## 8. Entregas posteriores y aceptación

Pasos de desarrollo revisables; ninguno autoriza activar escritores por separado:

| Paso | Archivos previstos (nombres nuevos sujetos a revisión) | Pruebas y aceptación antes del siguiente |
| --- | --- | --- |
| 1. Contrato/adaptador | common/schemas.py, nuevo common/mutation.py, DTO y routers gardens/plants/watering; docs/resources-api.md; pyproject.toml solo tras aprobar dependencia | Vectores JCS, duplicados/null/omisión, headers/ETag/revisiones, UUID generado estable; sin activar nuevos handlers en servicio |
| 2. Esquema/backfill | nuevas 0004_domain_revisions.py y 0005_mutation_gateway.py, db/models.py y módulos de modelos, tests/test_postgres.py | Upgrade desde 0003 con tombstones/referencias sin planta; colisión bloquea; FK/índices/FORCE/propietarios; fallo inyectado antes de commit revierte toda entrega; cero recibos/grupos históricos |
| 3. Gateway y atomicidad | cuerpo SQL versionado dentro de 0005; repositorio común; nuevos tests/test_mutations.py | Replay antes de CAS y tras borrado/renombrado; ID reutilizado distinto; terminal confirmado versus errores no durables; falla en datos/grupo/recibo revierte los tres y contador; respuesta perdida recupera originales |
| 4. Ocho escritores y lecturas | common/repository.py, services/repositories/routers/schemas de gardens/plants/watering, main.py para guardia de esquema; tests/test_resources.py | Todos invocan mismo gateway; ningún INSERT/UPDATE/DELETE de recurso por R; riego único/max histórico, edición sin eventos, no-op, jardines archivados conservan asignaciones, historial de planta borrada |
| 5. Seguridad/concurrencia y corte | tests/test_postgres.py, test_mutations.py, fixtures aisladas, docs/database.md y despliegue | Dos conexiones mismo owner: segundo espera y confirma secuencias contiguas; primer rollback libera número; replay paralelo solo un efecto; owners distintos aislados; constraints globales genéricos; DML directo/columnas/funciones privadas denegados; recibos/grupos/hechos inmutables; binario viejo no escribe; esquema incompatible no sirve recursos |

Pasos 2–4 son partes de una sola activación: no desplegar una migración parcial
con aplicación antigua abierta ni publicar un handler sin protocolo. Las pruebas
PostgreSQL futuras solo en base de pruebas y esquemas aislados según reglas actuales;
la ejecución contra desarrollo y cada cambio de permisos requieren autorización.

Mantener cobertura previa: auth/refresh/roles, owner isolation, validación de
campos, límites/paginación, planta+riego atómicos, snapshots históricos, eventos
manuales, ausencia de retroceso y protección de errores/secretos. Añadir expiración
de sesión antes de replay y no aceptar owner enviado por cliente.

Cambiar expectativas deliberadas, no borrar cobertura: requests sin headers pasan
a 422/428; garden DELETE con plantas deja de ser 409; revision int pasa a string;
PATCH no-op no avanza; 2147483647 deja de ser overflow de revisión (usar frontera
BIGINT); DML propio antes permitido ahora se deniega; pruebas de hard delete SET
NULL pasan a RESTRICT y verifican conservación; fixtures de historial huérfano
requieren identidad historical_only. Reintento con misma Key reproduce rechazo
terminal y no vuelve a evaluar reloj/CAS; nueva Key sí evalúa estado vigente.

Las 158 pruebas backend son evidencia anterior de 3.2D; las 319 pruebas Flutter,
análisis y builds web/APK son de implementación E.3, no de E.4A. Migración física
SQLite v1→v2 y cuatro comandos local_only se observaron en RMX5111 Android16/API36;
no verifican migraciones PostgreSQL. No se ejecutaron suites, SQL, builds ni pruebas
físicas en esta entrega documental.

## 9. Decisiones que requieren aprobación

- Gateway A con traslado de reglas y retirada completa del DML runtime, aceptando
  la frontera de confianza del GUC y el coste de mantener lógica PL/pgSQL.
- Contrato REST de §4: Key también en PATCH/DELETE, formato ETag/revisión string,
  cuerpos/headers reproducibles, errores durables, no-op y archivado; incompatibilidad
  deliberada con clientes 3.2D sin una ruta escritora antigua alternativa.
- Dependencia rfc8785==0.1.4 y envelope interno rest-v1; probar versión/entorno y
  vectores antes de adoptar, sin confundirlo con protocolo sync o outbox E.3.
- Esquema mínimo, FK RESTRICT, baseline/identidades/backfill y firmas/ACL exactas
  de §3/§6. Revisar resultados del preflight antes de autorizar ejecución real.
- Ventana de corte conjunto y estrategia de recuperación hacia delante; autorización
  separada para implementar/probar/migrar/cambiar permisos y para publicar Git.

Excluidos: endpoints sync/bootstrap/import/push/pull, instalaciones/sesiones móviles,
HTTP/cuentas Flutter, resolución UI de conflictos, catálogo administrativo, purga,
restauraciones destructivas, cifrado/backup Android y notificaciones. La configuración
Android E.3 se conservó, pero entrega física de notificación, corrupción, falta de
espacio, cortes eléctricos y restauraciones siguen sin comprobarse. Nada de E.4A
cierra esas limitaciones ni inicia implementación E.4.
