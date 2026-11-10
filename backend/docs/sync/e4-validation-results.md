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

> Estado vigente 2026-11-10: migración conjunta 0004+0005 de blueflora_dev.public
> ejecutada y comprobada mediante lecturas; head 0005_mutation_gateway, recuentos
> conservados y R1 aceptada. Readiness temporal correcta y proceso cerrado.
> Véase [resultado de migración](e4-development-migration-results.md). Sin despliegue persistente ni cierre de E.4.
> Las secciones anteriores/planes históricos se conservan como antecedentes.

# E.4 — implementación y pruebas aisladas

Estado: **implementada y validada en pruebas; pendiente de revisión, sin cierre**.
Fecha: 2026-11-09. Base Git: af2bd84dadae3fba8a8fd8119c54a2307520cfa9.
No migración de desarrollo, despliegue, commit, push, tags ni releases.

## Entrega implementada

Gateway único `S.resource_apply(uuid,text) RETURNS jsonb` para las ocho mutaciones.
Routers adaptan HTTP; servicios/repositores conservan lecturas, autenticación,
contexto local y transacción. SQL decide relaciones/archivado, CAS, reloj servidor,
identidades, no-op, snapshots, baseline y proyección max de riegos; persiste datos,
contador, grupo y recibo en una transacción. No hay escritores DML de recursos en
los módulos Python ni alternativa al gateway bajo runtime.

Replay antes de CAS/estado/reloj, comparación de hash y bytes, errores terminales
confirmados sin grupo, respuestas originales serializadas y respuestas solo después
del COMMIT. Reintentos hasta tres para 40P01/40001 con la misma intención. No purga.

Contrato incompatible 3.2D actualizado en resources-api.md y OpenAPI: Key en ocho
mutaciones, If-Match en PATCH/DELETE, revisión string/BIGINT, ETag/Location,
no-op y jardines archivables. Campos desconocidos/duplicados/null inválido,
profundidad y bytes se comprueban antes de procesamiento desproporcionado. Streaming
no permite saltarse 65536 bytes. NUL no representable en PostgreSQL text se rechaza;
no se altera texto Unicode para hacerlo encajar.

ETag fuerte cubre todos los campos REST individuales almacenados. Ningún DTO une
nombre de jardín/especie u otro atributo mutable relacionado. GET y respuesta
persistida tienen exactamente los mismos bytes SQL, incluidas fechas y números;
una representación cambiada obtiene revisión/ETag nuevos. Snapshot histórico no
cambia tras renombrar/borrar planta; jardín renombrado no cambia representación
de planta. No se necesitaron cascadas nuevas de revisiones.

## Migraciones y privilegios

0001–0003 intactas. Nuevas 0004_domain_revisions y 0005_mutation_gateway:

- Jardines: revisión BIGINT, updated_at y tombstone; plantas: BIGINT y baseline.
- Identidades full/historical_only con FK por owner; revisión full acompaña planta.
  Backfill conserva todas las columnas anteriores y no inventa filas de planta,
  fechas, eventos, recibos o grupos. Owner_state inicia contador 0 para existentes;
  nuevas cuentas lo crean perezosamente en gateway, sin cambiar auth_register.
- FK históricas y species→plants pasan a RESTRICT; no SET NULL silencioso de hechos
  o relaciones fuera del feed. Historial y referencias retenidos tras tombstone.
- owner_state, operaciones y grupos privados, todos con FORCE RLS y USING/WITH
  CHECK por owner. Contador transaccional, grupos append-only, FK diferidas cruzadas
  entre recibo y grupo; sin BIGSERIAL como orden de confirmación. Imágenes incluyen
  entity_type/entity_id/revision/state compatibles con E.1, sin endpoint sync.
- Límite 64 KiB medido con el grupo completo, metadatos incluidos. Backfill utiliza
  imágenes con columnas/fechas finales y secuencia de longitud máxima. Casos de
  64000 bytes heredados conservados y 65536 más envoltorio bloqueados sin truncar.
- Funciones propiedad de migrador, `search_path=pg_catalog,pg_temp`; gateway
  SECURITY DEFINER y timezone UTC; reject_immutable() SECURITY INVOKER. Referencias
  cualificadas, sin SQL dinámico en gateway, defaults o sobrecargas.

Delta exacto para R (API correspondiente) en objetos S del esquema de prueba:

- REVOKE INSERT, DELETE ON S.gardens FROM R.
- REVOKE UPDATE(name,description) ON S.gardens FROM R.
- REVOKE INSERT ON S.plants FROM R.
- REVOKE UPDATE(garden_id,species_id,name,species_label,initial_height_m,
  watering_frequency_days,last_watered_at,revision,deleted_at,updated_at)
  ON S.plants FROM R.
- REVOKE INSERT ON S.growth_history FROM R; igual para S.watering_events.
- REVOKE ALL sobre cada una de plant_identities, sync_owner_state, sync_operations
  y sync_change_groups FROM PUBLIC,R; ningún SELECT directo nuevo para R.
- REVOKE ALL ON FUNCTION S.resource_apply(uuid,text) FROM PUBLIC;
  GRANT EXECUTE de esa firma TO R.
- REVOKE ALL ON FUNCTION S.reject_immutable() FROM PUBLIC,R.

SELECT de recursos y permisos auth anteriores se conservan. No GRANT sobre tablas
futuras, atributos/membresías/contraseñas de roles, extensiones o permisos generales.
Triggers BEFORE UPDATE/DELETE protegen hechos, recibos y grupos, incluso al escribir
como M sin alterar DDL. El administrador sigue pudiendo cambiar DDL; no se promete
protección contra él. El GUC depende de conexión API confiable y no es identidad
infalsificable ante credenciales runtime comprometidas.

## Entorno, destinos y comandos ejecutados

Python existente 3.14.4; `rfc8785==0.1.4` instalado únicamente en backend/.venv,
Apache-2.0, sin dependencias runtime adicionales. Solo una línea añadida a
pyproject.toml y requirements.lock; ninguna otra versión actualizada.

Se verificaron por conexión base y rol antes de crear esquemas:
blueflora_test/blueflora_test (migración), blueflora_test/blueflora_api_test (API).
Solo esquemas propios `bf_test_<uuid>`; search_path y transacción externa comprobados
por el mecanismo Alembic existente. No DDL/DML sobre public, bases de desarrollo,
objetos compartidos o ajenos. Fixtures transaccionales revierten DDL/datos; fixtures
concurrentes retiran exclusivamente su esquema efímero creado durante el caso.
No se imprimen ni adjuntan datos, bases, respaldos o credenciales.

Desde backend con su Python virtual:

| Comando | Resultado |
| --- | --- |
| `.venv/bin/python -m pip install --no-deps rfc8785==0.1.4` | Instalación aprobada correcta; sin upgrade de otros paquetes |
| `.venv/bin/python -m pip check` | No broken requirements found |
| `.venv/bin/python -m pytest -q -W error --tb=short` | **220 aprobadas**, cero fallos/omisiones/warnings; ejecución final 164.97 s |
| Pruebas focalizadas de CRUD/migración tras corregir guardia | 8 aprobadas antes de la suite final |
| Comparación Alembic compare_metadata en esquema aislado | Sin diferencias con Base.metadata; incluida en suite final |
| `git diff --check` y revisión de whitespace en archivos nuevos | Sin incidencias |

Las 158 pruebas previas se conservaron adaptando expectativas deliberadas; se
sumaron 62 casos. No se ejecutaron comandos CLI check-schema/upgrade sobre public
para obtener ese resultado. Comparación y migraciones ocurrieron en esquemas propios.

Durante iteraciones se corrigieron nombres de restricciones de metadatos, manejo
de %ROWTYPE en el driver, parámetro de esquema en la guardia, representación GET
idéntica al recibo y errores de contexto/comparación en pruebas nuevas. Una captura
anterior de IntegrityError se retiró: restricciones inesperadas ahora son 503 con
rollback, no conflictos de negocio falsos. Hubo pasadas intermedias fallidas y una
pasada previa de 218 aprobadas. Se repitió la suite al cambiar código/guardia/límite
completo, no por cambios documentales. El resultado final válido es el de 220.

## Evidencia verificable

- Los 24 números finitos del apéndice B RFC8785 pasan desde bits IEEE754; NaN,
  infinitos y demás entradas no admitidas fallan. Unicode UTF-16, controles,
  NFC/NFD distinto, omisión/null, UUID/instantes normalizados y binary64 extremo
  cubiertos. Hashes Python/SQL coinciden para todo ese corpus numérico y Unicode.
  Una huella igual simulada con bytes distintos también se rechaza.
- Replay reproduce status/cuerpo/Location/ETag tras editar y borrar; Key con otra
  intención da operation_id_reused. Sesión revocada se rechaza antes de replay.
  Fecha futura/rechazo CAS quedan durables; corregir requiere nueva Key. UUID
  generado después de lookup se conserva al repetir la intención omitida.
- Respuesta descartada después de COMMIT se recupera mediante recibo. Es simulación
  del resultado perdido en el proceso, no una prueba de corte físico de red.
- Fallos sintéticos en datos, grupo y recibo, incluyendo una restricción inesperada,
  dejan cero cambios parciales/contador consumido. Reintentar la Key tras retirar
  el fallo aplica una sola vez. Fronteras BIGINT revierten el evento/proyección.
- Dos conexiones del mismo owner se bloquearon realmente: pg_blocking_pids confirmó
  la espera. Si confirma el primero, grupos 1 y 2; si revierte, solo grupo 1 del
  segundo. Dos owners avanzan independientemente; misma Key tiene namespace propio.
  Reintento concurrente de riego no duplica evento ni revisión.
- Runtime real no dispone de DML, incluso permisos de columna; no ve tablas privadas
  ni hashes/sesiones. PUBLIC sin permisos nuevos. Hechos/grupos/recibos no admiten
  UPDATE/DELETE. Esquema/head/trigger incompatible impide recursos y arranque;
  liveness sigue independiente de consultas de recursos.
- Upgrade desde 0003 conserva UUID, todos los campos/fechas, tombstones y snapshots.
  Colisiones full/históricas de owners distintos bloquean. Un fallo antes del
  COMMIT externo revierte ambas migraciones/grants/datos; recibos y grupos previos
  inicialmente vacíos, sin inventar comandos históricos.
- Jardín archivado conserva vínculos; no admite nuevas asignaciones. Riego antiguo
  no retrocede calendario; edición no fabrica hechos; nombre histórico retenido.

Expectativas cambiadas: headers obligatorios, revisión string/BIGINT, garden DELETE
archiva en vez de 409 con referencias, PATCH no-op no incrementa, DELETE repetido
exige precondición/replay, DML antes permitido se deniega, hard-delete SET NULL se
sustituye por RESTRICT, fixtures huérfanas requieren identidad historical_only.
Las pruebas originales de downgrade 0001–0003 siguen cubiertas antes de E.4; después
de E.4 se verifica negativa expresa a downgrade destructivo.

## Precisiones respecto de E.4A y pendientes

La firma aprobada admite `resource_apply(NULL,NULL)` como consulta sin DML del head,
para no conceder SELECT de alembic_version a runtime. La guardia verifica además
propietarios, esquema/columnas/ACL/FORCE, función y triggers al arrancar y por
transacción. No se añadió otra función privilegiada o permiso de metadatos.
El cuerpo SQL se versiona en 0005_mutation_gateway.sql, cargado por esa migración,
para revisar sus reglas separadamente; forma parte inseparable de 0005.

JCS canonicaliza intención, no la respuesta REST. PostgreSQL puede expandir el
número binary64 máximo como literal entero decimal; reconvertir a binary64 conserva
el valor y GET/replay conservan bytes. No se cambia el dominio a Decimal arbitrario.
Se rechazan NUL y enteros de entrada que perderían precisión al convertirse.

No bloqueo administrativo pendiente en pruebas. Falta autorizar y ejecutar el
[preflight/corte de desarrollo](e4-deployment.md); sus datos, volúmenes, ACL reales,
respaldo y ventana no se consultaron ni verificaron aquí. No se provocó deadlock
real; sí espera concurrente, rollback y reintentos 40001 simulados/acotados; 40P01
usa el mismo tratamiento. Sin prueba de red física, desastre PostgreSQL o restore.
No sustituir esos límites con resultados de tests sintéticos.

Las 319 pruebas Flutter y builds/análisis anteriores son de E.3, igual que la
migración física RMX5111 Android16/API36. No se repitieron ni se operó el teléfono.
Notificación física, corrupción, falta de espacio, cortes eléctricos/restauraciones
siguen sin comprobarse. Sin sync/bootstrap/import, móviles/cuentas Flutter, cambios
Android, purga, tags, releases o publicación Git. E.4 no está cerrada.

## Archivos de la entrega y estado Git

40 archivos de backend/documentación, incluidos los dos cambios E.4A previos
conservados y actualizados. Índice vacío; main mantiene el commit base.
.vscode/ permanece sin rastrear, fuera de la entrega. Sin archivos Flutter,
secretos, bases, respaldos ni productos de compilación.

- `backend/README.md`
- `backend/app/db/models.py`
- `backend/app/main.py`
- `backend/app/modules/common/models.py`
- `backend/app/modules/common/mutation.py`
- `backend/app/modules/common/repository.py`
- `backend/app/modules/common/schemas.py`
- `backend/app/modules/gardens/models.py`
- `backend/app/modules/gardens/repository.py`
- `backend/app/modules/gardens/router.py`
- `backend/app/modules/gardens/schemas.py`
- `backend/app/modules/gardens/service.py`
- `backend/app/modules/plants/models.py`
- `backend/app/modules/plants/repository.py`
- `backend/app/modules/plants/router.py`
- `backend/app/modules/plants/schemas.py`
- `backend/app/modules/plants/service.py`
- `backend/app/modules/watering/models.py`
- `backend/app/modules/watering/repository.py`
- `backend/app/modules/watering/router.py`
- `backend/app/modules/watering/schemas.py`
- `backend/app/modules/watering/service.py`
- `backend/docs/architecture.md`
- `backend/docs/database.md`
- `backend/docs/resources-api.md`
- `backend/docs/sync/README.md`
- `backend/docs/sync/e4-deployment.md`
- `backend/docs/sync/e4-validation-results.md`
- `backend/docs/sync/e4a-contract-gateway-migration.md`
- `backend/migrations/versions/0004_domain_revisions.py`
- `backend/migrations/versions/0005_mutation_gateway.py`
- `backend/migrations/versions/0005_mutation_gateway.sql`
- `backend/pyproject.toml`
- `backend/requirements.lock`
- `backend/tests/test_auth.py`
- `backend/tests/test_mutation_migration.py`
- `backend/tests/test_mutations.py`
- `backend/tests/test_postgres.py`
- `backend/tests/test_resources.py`
- `docs/TRANSICION_TECNICA.md`

## Adenda R1 — 2026-11-09

[Guardia y evidencia R1](e4-r1-capabilities.md): 31 pruebas focalizadas aprobadas
(28 nuevas y 3 de rollback conservadas), después suite backend completa con
**248 aprobadas en 172.65s**, -W error. pip check y git diff --check correctos.
El resultado anterior de 220 es el antecedente de implementación; 248 corresponde
a esta ejecución posterior. Solo esquemas efímeros de blueflora_test, sin roles
globales nuevos, actualización de dependencias ni operaciones en desarrollo.
E.4 permanece abierta y el respaldo/restauración/corte siguen pendientes.


## Compatibilidad exacta del CHECK restaurado — 2026-11-10

[Informe de compatibilidad](e4-check-compatibility-results.md): 72 pruebas
focalizadas aprobadas en 22.93 s y suite backend completa **292 aprobadas en
178.88 s**, con -W error. pip check y git diff --check correctos. Los recuentos
220/248 anteriores se conservan como antecedentes. La reevaluación offline del
ensayo ya ejecutado dio MATCH con bf-restore-inventory-v2; no hubo nueva
restauración del respaldo ni arranque del clúster conservado. E.4 sigue abierta,
sin migrar desarrollo ni autorizar el corte.
