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

> Actualización posterior: R1 fue corregido y validado únicamente en esquemas
> aislados; véase [corrección R1](e4-r1-capabilities.md). Este informe conserva
> el preflight histórico; su ejemplo de restore en el clúster real queda
> sustituido por el destino aislado descrito en esa adenda. Desarrollo no se modificó.

# E.4 — revisión final y preflight de desarrollo

Fecha: 2026-11-09, America/Mexico_City. **E.4 abierta; corregir antes de migrar.**
Solo revisión, consultas READ ONLY y esta documentación. No migraciones, DML,
cambios de permisos/roles, despliegue, respaldos/restauraciones, publicación Git,
Flutter o teléfono. Las 220 pruebas aprobadas son evidencia de la implementación
anterior; no se repitieron suites ni fixtures PostgreSQL en esta revisión.

## 1. Git, alcance y copia de fuentes

main/HEAD: af2bd84dadae3fba8a8fd8119c54a2307520cfa9. Al comenzar había 40 archivos
de entrega (30 modificados, 10 nuevos sin rastrear), índice vacío y .vscode/ aparte.
Se conservaron los cambios anteriores. Esta revisión añade este informe y actualiza
únicamente e4-deployment.md; ningún archivo ejecutable o migración fue corregido.

Los ocho handlers de escritura contienen una única llamada al adaptador mutate:
altas/ediciones/borrados de jardines y plantas, growth y watering. Mutate llama
ResourceRepository.apply, que autentica/contextualiza en la misma transacción e
invoca resource_apply. No quedan INSERT/UPDATE/DELETE de recursos en sus
repositorios/servicios Python. Auth conserva sus funciones existentes; no es feed
de credenciales. 0001_initial, 0002_auth y 0003_resource_permissions coinciden
byte a byte con HEAD. No cambios Flutter, herramientas o dependencias adicionales.
La única dependencia nueva sigue siendo rfc8785==0.1.4. No se encontraron indicios
de secretos, bases, respaldos o builds dentro de los cambios de entrega; no se
leyó/imprimió el contenido de .env, argv/env de procesos o archivos de credenciales.
La carga de configuración existente resolvió las conexiones sin exponer secretos.

Headers/errores/revisiones string/BIGINT, archivado y FK RESTRICT corresponden a
E.4A. El delta de permisos de 0005 retira también los UPDATE por columna y mantiene
auth intacto; no añade roles o membresías ni permisos generales. El nuevo modo
(NULL,NULL) es una precisión añadida durante la implementación y se evalúa abajo.

**SQL de 0005:** se copiaron 82 archivos fuente del backend (rastreados y nuevos),
sin .env, .venv ni .git, a un directorio temporal; desde otro cwd se cargó el módulo
0005 y se ejerció upgrade con un doble de conexión/contexto exclusivamente en
memoria. Path(__file__).with_suffix('.sql') encontró el archivo hermano; el payload
cualificado coincidió íntegramente con el origen, sin placeholders pendientes
(23143 bytes en el esquema de comprobación). No se conectó a PostgreSQL ni se
ejecutó SQL/migración en ese ensayo. Esto verifica empaquetado de fuentes y carga,
no repite el ensayo de migración real de las 220 pruebas.

El sidecar SQL sigue sin rastrear, igual que 0004/0005 y demás archivos nuevos:
la publicación futura debe incluirlos explícitamente. Un checkout de HEAD todavía
solo contiene E.3. Se verificó una copia íntegra de la entrega de trabajo, no un
commit E.4 inexistente. Un wheel app-only no es el artefacto de despliegue completo:
pyproject empaqueta app; hay que distribuir también alembic.ini y migrations/.

## 2. Consulta de capacidades: evaluación y hallazgo

Referencias: migrations/versions/0005_mutation_gateway.sql, entrada de
resource_apply; app/modules/common/repository.py, verify_schema.

| Caso | Evaluación por inspección; no invocado en desarrollo |
| --- | --- |
| (NULL,NULL) | Lee head como M y, si es 0005, devuelve solamente {"ready":true}; ningún dato de propietario |
| DML / owner_state | Retorna antes del primer INSERT, locks de owner, ledger y contador; no crea owner_state |
| Contexto | No establece owner_id/auth_internal. SET search_path/timezone son configuración local de función, restaurada al salir; o lee/castea el contexto al entrar, no lo autentica |
| (NULL,valor) | Rechazado por p_operation_id null, SQLSTATE 42501, antes de DML |
| (valor,NULL) | Sin owner: 42501; con owner válido: la validación del envelope falla con 22023 (format NULL IS DISTINCT FROM rest-v1). No llega al INSERT |
| Autenticación | No existe endpoint HTTP de probe. Las mutaciones HTTP siguen validando access mediante auth_access antes de fijar owner. Una conexión SQL comprometida puede fijar GUC: límite de confianza ya aprobado, no una garantía nueva |
| Capacidad real | El modo SQL solo comprueba head. No es un éxito incondicional, pero tampoco acredita por sí solo capacidades completas |

verify_schema añade propietario/SECURITY DEFINER/search_path/EXECUTE/PUBLIC,
USAGE/sin CREATE de esquema, ocho tablas con RLS/FORCE y sin DML runtime, ausencia
de lectura privada, permisos de columna, diez tipos/columnas requeridos y cuatro
triggers habilitados con OID esperado. El chequeo combinado es más que el marker SQL.

**Hallazgo R1, corregir antes del corte:** el manifiesto está incompleto. No consulta
pg_policies para validar USING/WITH CHECK, roles/operaciones o políticas extra;
tampoco comprueba PK/UNIQUE/FK/CHECK y sus propiedades esenciales. Mantener head,
FORCE y esos tipos mientras cambia una política o desaparece una restricción puede
pasar la guardia. Asimismo, el probe directo devuelve ready aunque falle una
capacidad comprobada solo después por Python. Es una carencia de detección de
drift/incompatibilidad, no evidencia de una política incorrecta en desarrollo hoy.
No se alteró ningún objeto para reproducirla en desarrollo.

Cobertura existente revisada:

- test_readiness_on_startup_and_broken_capability prueba arranque válido y un
  trigger deshabilitado; detecta el fallo la guardia Python, no el marker SQL solo.
- test_runtime_acl_public_immutable_and_schema_failure cambia el head en un esquema
  de prueba y verifica 503; conserva liveness independiente.
- test_replay_original_bytes_headers_after_edit_delete_and_invalid_session cubre
  sesión revocada antes de replay, no las variantes NULL del SQL.
- No hay prueba directa de las cuatro combinaciones de argumentos, READ ONLY del
  probe, ausencia de cambios en filas/contadores/GUC o políticas/constraints
  incompatibles manteniendo head. Las 220 aprobadas no cubren esas afirmaciones.

**Corrección propuesta, no implementada:** mantener firma/ACL/contrato REST;
rechazar explícitamente exactamente un argumento NULL antes del parser. Hacer que
el modo de capacidades valide un manifiesto cerrado por esquema/owner/rol esperado,
incluyendo políticas, constraints/índices relevantes, tipos, ACL y función/trigger.
Puede centralizarse la parte privilegiada en el modo de metadatos existente; Python
no debe interpretar un simple head como readiness completa. No conceder acceso
directo a alembic_version ni añadir funciones/grants genéricos. Evitar duplicar
manifiestos contradictorios entre SQL/Python; documentar claramente la frontera.

Pruebas futuras mínimas en esquemas efímeros: probe desde transacción READ ONLY,
sin owner y con contexto propio; snapshots de filas/contadores/GUC antes/después;
NULL parciales rechazados sin cambios; ausencia de autenticación HTTP no permite
mutación; head correcto con política alterada, FK/unique ausente o trigger inválido
falla cerrado; éxito con manifiesto íntegro y sin información privada. Primero
focalizadas; después suite completa porque se modifica guardia/gateway. Requiere
autorización de corrección/pruebas; no se ejecutaron en esta revisión.

## 3. Preflight real: método y resultados

Conexiones existentes, sin URLs/credenciales en salida. Desde la conexión se impuso
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY, con
**default_transaction_read_only=on ya en la conexión**, antes de consultar objetos.
Se verificaron database/user/public/read_only y que el rol no fuera super/BYPASS.
Cada transacción terminó en ROLLBACK. No se llamó ninguna función de aplicación,
incluidas auth_* o resource_apply, ni se hicieron locks FOR UPDATE.

Para el inventario de owners se usó únicamente SET LOCAL auth_internal y la política
SELECT ya existente para M; no se cambió RLS/ACL ni se concedió acceso. Se restauró
el contexto transaccional. Se consultaron solo IDs para enumeración y agregados;
ningún email, hash, token, nombre o payload salió del servidor para el informe.

| Comprobación | Resultado |
| --- | --- |
| Base / esquema | blueflora_dev / public en ambas conexiones |
| Migrador / API | blueflora_dev / blueflora_api |
| PostgreSQL | 18.6 (Ubuntu 18.6-0ubuntu0.26.04.1) |
| Alembic real | 0003_resource_permissions, una fila |
| Dueño de base / tablas / 7 funciones auth | blueflora_dev |
| Dueño de public | pg_database_owner; M tiene USAGE/CREATE por propiedad de base; R solo USAGE |
| Roles M y R | LOGIN, sin superuser/BYPASSRLS/CREATEDB/CREATEROLE/REPLICATION; sin membresías explícitas. R NOINHERIT |
| Tablas privadas actuales | 8 con RLS y FORCE; species y alembic_version son las excepciones esperadas |
| Políticas | owner_isolation con USING/WITH CHECK equivalentes; auth_internal limitada a M, users SELECT/INSERT según 0002 |
| PUBLIC | Solo USAGE de public; ningún privilegio explícito en tablas/columnas ni EXECUTE de las 7 auth_* |
| Grant options / default ACL personalizadas | 0 / ninguna para M o R |
| Restricciones / índices | Todos los inspeccionados validados / válidos y listos |
| Funciones incorporadas | sha256(bytea) y gen_random_uuid() presentes y ejecutables por M/R |
| E.4 en desarrollo | 0 tablas E.4, resource_apply/reject_immutable inexistentes; esperado antes de migrar |
| Tipo actual de plants.revision | INTEGER; gardens aún sin revision/updated_at/deleted_at |
| Conexiones de otros clientes al muestrear | 0 en blueflora_dev |

Privilegios reales actuales, exactamente 3.2D:

- gardens: SELECT/INSERT/DELETE; UPDATE(name,description).
- plants: SELECT/INSERT; UPDATE(garden_id,species_id,name,species_label,
  initial_height_m,watering_frequency_days,last_watered_at,revision,deleted_at,updated_at).
- growth_history y watering_events: SELECT/INSERT; species: SELECT.
- users: SELECT(id,email,is_active,created_at), sin SELECT general/hash.
- Tablas auth y alembic_version: ningún privilegio directo para R; las siete
  firmas auth conservan EXECUTE, propietario M y search_path seguro.
- CONNECT/TEMP de base disponibles para R; sin CREATE de base/esquema. TEMP no es
  un permiso nuevo E.4 ni se retiró. Los INSERT efectivos por columna proceden de
  sus grants de tabla, no de concesiones separadas que se hayan omitido al revocar.

### Recuentos y compatibilidad

| Datos actuales | Recuento |
| --- | ---: |
| users / auth_sessions / auth_refresh_tokens / auth_rate_limits | 0 cada tabla |
| gardens / plants / growth_history / watering_events / species | 0 cada tabla |
| Plantas activas / eliminadas | 0 / 0 |
| Identidades históricas sin planta / reclamadas por varios owners | 0 / 0 |
| Relaciones contradictorias, FK owner/relación inválidas | 0 |
| Revisiones no positivas/sin margen BIGINT | 0 |
| Fechas no finitas/futuras incompatibles | 0 |
| Grupos proyectados que excedan 65536 bytes | 0 |
| Máximo de imagen/grupo y suma proyectada por tipo | 0 bytes |

Usuarios enumerados con la política interna existente: cero. Los FK owner→users
validados, sin escrituras concurrentes visibles en el snapshot, permiten concluir
que recursos sin owner no están ocultos tras un simple SELECT sin contexto.
La lectura con R sin contexto también devuelve cero, pero no se usa esa lectura
sola como prueba de base vacía.

**Límite:** colisiones, fechas y tamaños son ausencia de casos en una base vacía;
no son un nuevo ensayo de preservación ni de carga grande. Los casos no vacíos
siguen respaldados únicamente por las pruebas sintéticas anteriores. No se puede
estimar duración/bloqueos de una migración con datos grandes con este inventario.
No se midió espacio libre del volumen servidor ni se certificó una ventana real.
El snapshot puede quedar obsoleto: repetir comprobaciones al preparar el corte.
No hubo comprobaciones bloqueadas por FORCE RLS ni ampliación de permisos.

## 4. Respaldo y escritores

No respaldo PostgreSQL conocido/validado acreditado en documentación ni artefactos
de backup en backend/docs y sus raíces inspeccionadas (sin abrir archivos de backup).
No se recorrieron ubicaciones privadas arbitrarias fuera del proyecto: esto **no**
prueba que no exista una copia externa del usuario. No hay evidencia de restore.
archive_mode=off; wal_level=replica; fsync/full_page_writes=on; estadísticas de
archivado: 0 archivados, 0 fallidos. No hay evidencia de PITR/WAL archivado continuo.
pg_dump y pg_restore locales: 18.6; solo se consultó --version.

No candidatos Python/uvicorn/gunicorn con cwd dentro del proyecto al muestrear,
ni unidades de servicio/compose versionadas identificadas. No se leyeron argv/env.
Esto y cero conexiones SQL son observaciones puntuales, no prueba de ausencia de
cron, servicio con otro cwd, contenedor o cliente externo programado.

Antes del corte hay que identificar y parar el API completo (incluye register,
login/refresh/logout que escriben auth), workers/importadores/SQL administrativos
si existen, y mantenimiento de catálogo. No basta bloquear ocho endpoints de
recursos. No terminar otros proyectos ni sesiones PostgreSQL automáticamente.

## 5. Plan exacto propuesto, no ejecutado

### A. Condiciones de entrada

Autorizar primero R1 y sus pruebas aisladas, revisar el nuevo diff y aprobar el
artefacto completo de fuentes (incluido SQL). Identificar operador/rol existente de
respaldo, destino privado y destino de restauración de ensayo. Identificar cómo se
supervisa realmente el API; actualmente no hay una unidad/PID confirmada que parar.
No cambiar roles, contraseña, membresías, pg_hba o archivado como efecto lateral.

### B. Drenar y volver a verificar destino/actividad

Si el API está en la terminal descrita por README, parada controlada con Ctrl+C.
Si se confirma una unidad propia, el comando depende del nombre real, por ejemplo
`systemctl --user stop "$BF_E4_UNIT"` solo después de identificarla y autorizarla.
No existe un nombre de unidad confirmado para sustituir esa variable hoy.

Consulta propuesta con autenticación interactiva existente (no ejecutada aquí):

```bash
PGOPTIONS='-c default_transaction_read_only=on' \
psql -X -W -h 127.0.0.1 -U blueflora_dev -d blueflora_dev -v ON_ERROR_STOP=1 <<'SQL'
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT current_database(), current_user, current_schema(), current_setting('transaction_read_only');
SELECT version_num FROM public.alembic_version;
SELECT usename,backend_type,state,count(*)
FROM pg_stat_activity
WHERE datname=current_database() AND pid<>pg_backend_pid()
GROUP BY usename,backend_type,state;
ROLLBACK;
SQL
```

Exigir destino/head esperados, nueva revisión de datos/ACL y cero escritores
pendientes. Resolver sesiones con propietario del proceso, sin pg_terminate_backend
automático. Impedir que supervisores reabran binarios antiguos durante la ventana.

### C. Respaldo coherente y prueba de recuperación

El migrador blueflora_dev está sujeto a FORCE RLS y no tiene BYPASSRLS. No asumir
que su pg_dump produce una copia completa: el comportamiento normal rechaza tablas
filtradas, y --enable-row-security podría dar una copia parcial. **No usar esa
opción como solución ni crear un rol BYPASS.** Un DBA debe identificar/autorizar una
identidad de respaldo ya existente con lectura íntegra de las tablas; hoy no está
acreditada. Si no existe, bloquear respaldo/corte y pedir decisión administrativa.

Comandos propuestos, previa autorización y selección de BF_E4_DBA_ROLE existente:

```bash
set -euo pipefail
BF_E4_BACKUP_DIR=/home/niereme/.local/share/blueflora/backups
mkdir -p -- "$BF_E4_BACKUP_DIR"
chmod 700 -- "$BF_E4_BACKUP_DIR"
BF_E4_BACKUP_FILE="$BF_E4_BACKUP_DIR/blueflora_dev-pre-e4-$(TZ=America/Mexico_City date +%Y%m%dT%H%M%S).dump"
(
  umask 077
  set -o noclobber
  PGUSER="${BF_E4_DBA_ROLE:?Seleccionar rol existente autorizado}" \
    pg_dump -W -h 127.0.0.1 -d blueflora_dev --format=custom > "$BF_E4_BACKUP_FILE"
)
pg_restore --list "$BF_E4_BACKUP_FILE" > /dev/null
sha256sum -- "$BF_E4_BACKUP_FILE" > "$BF_E4_BACKUP_FILE.sha256"
```

No continuar si pg_dump termina con error ni conservar un archivo incompleto como
respaldo válido. El listado/hash verifica formato e integridad, **no recuperación**.
No imprimir contenido del dump ni adjuntarlo al informe. Con todos los escritores
parados, el snapshot lógico incluye datos y esquema coherentes; documentar versión,
head, hashes de fuentes y recuentos agregados del corte en el directorio privado.

Ensayo posterior, con autorización separada de DBA para un destino nuevo y aislado:

```bash
set -euo pipefail
# BF_E4_RESTORE_DB: nombre nuevo aprobado; nunca blueflora_dev/blueflora_test.
[[ "${BF_E4_RESTORE_DB:?}" =~ ^blueflora_e4_restorecheck_[0-9]{8}_[0-9a-f]{8}$ ]]
createdb -W -h 127.0.0.1 -U "${BF_E4_DBA_ROLE:?}" --template=template0 "${BF_E4_RESTORE_DB:?}"
pg_restore -W -h 127.0.0.1 -U "$BF_E4_DBA_ROLE" \
  --exit-on-error --single-transaction --dbname="$BF_E4_RESTORE_DB" "$BF_E4_BACKUP_FILE"
```

Verificar en ese destino head/owners/ACL/FORCE/FK/índices y todos los recuentos,
con transacciones de lectura y sin ejecutar funciones mutadoras. No omitir
owners/ACL para luego afirmar recuperación íntegra. No restaurar encima de una
base existente. No usar los comandos de la app contra un nombre distinto de sus
destinos permitidos, ni relajar las protecciones de conexión para ese ensayo.
Crear base/restaurar/limpiar ese destino y sus permisos requieren autorización
específica; no están cubiertos por esta revisión.

### D. Migración conjunta, únicamente tras nueva autorización

Desde la copia completa revisada, escritores detenidos y respaldo recuperable:

```bash
cd /home/niereme/Documents/Blueflorapp/backend
.venv/bin/python -m app.db.manage current
.venv/bin/python -m app.db.manage upgrade
.venv/bin/python -m app.db.manage current
.venv/bin/python -m app.db.manage check-schema
```

Esperar 0003 antes y 0005_mutation_gateway después. env.py mantiene engine.begin
externo para 0004+0005; ninguna revisión contiene COMMIT/autocommit. No desplegar
0004 como estado intermedio ni reabrir el escritor antiguo con permisos extra.
check-schema es comparación de modelos, no sustituye auditoría de políticas/ACL.

Comprobación de capacidad con runtime **después de corregir R1 y autorizar el corte**:

```bash
.venv/bin/python - <<'PY'
from app.core.config import Settings
from app.db.connection import create_api_engine, verify_api
from app.modules.auth.repository import AuthRepository
from app.modules.common.repository import ResourceRepository
engine=create_api_engine(Settings(),'development')
try:
    repository=ResourceRepository(AuthRepository(engine))
    with engine.connect() as connection:
        connection.exec_driver_sql('SET TRANSACTION READ ONLY')
        verify_api(connection,'development')
        repository.verify_schema(connection)
        connection.rollback()
    print('Capacidades de desarrollo verificadas en READ ONLY.')
finally:
    engine.dispose()
PY
```

Revisar además FK/integridad, recuentos conservados y cero recibos/grupos históricos,
ausencia de DML/UPDATE de columna runtime, firmas/propietarios/PUBLIC y carga desde
el artefacto final. Luego autorizar arranque del nuevo servicio con su supervisor
real; si es manual, comando de README sin --reload:
`.venv/bin/python -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000 --no-proxy-headers`.
No ejecutarlo en esta revisión. Escrituras de humo en desarrollo necesitarían su
propia autorización/datos descartables; no se incluyen tácitamente en checks SQL.

### E. Recuperación

Antes del COMMIT externo, error de 0004/0005 revierte datos/DDL/grants de ambas;
comprobar head/ACL/recuentos originales antes de volver al binario anterior.
COMMIT incierto: comprobar estado, no repetir downgrade/restore a ciegas.
Después del COMMIT: mantener escritores cerrados si falla verificación/arranque,
conservar ledger/feed/datos y corregir hacia delante. Nunca reotorgar DML al binario
viejo. Después de aceptar operaciones nuevas, una copia previa pierde ACK/datos;
no es rollback seguro. Restore de desastre requiere reconciliación/autorización
específicas. Con archivado WAL desactivado no se promete recuperar todas las
escrituras posteriores al dump: acordar respaldo posterior/RPO o protección WAL
mediante una autorización administrativa aparte, sin cambiarla aquí.

## 6. Recomendación y autorizaciones necesarias

**Corregir antes de avanzar**, aunque el preflight de la base vacía no encontró
incompatibilidades de datos o privilegios inesperados. R1/cobertura y recuperación
acreditada son puertas pendientes. No hay aprobación de cierre E.4.

1. Corregir guardia/probe y añadir sus pruebas en blueflora_test aislado; si sigue
   sin aplicarse en desarrollo, revisar 0005 nueva, nunca modificar 0001–0003.
2. Seleccionar identidad existente, ruta y método de respaldo completo; crear y
   verificar el respaldo. Resolver cualquier necesidad administrativa por separado.
3. Autorizar destino/operador/restauración de ensayo; acreditar recuperación.
4. Aprobar ventana, identificación/parada de escritores, repetición del preflight,
   migración conjunta y comprobaciones posteriores de desarrollo.
5. Autorizar despliegue/arranque del nuevo binario y, si se desea, escrituras de humo.
6. Publicación Git (commit/push) y fases posteriores siguen requiriendo autorización
   independiente. No introducirlas en la autorización del corte.
