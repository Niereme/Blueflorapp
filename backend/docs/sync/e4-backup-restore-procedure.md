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

# E.4 — procedimiento ejecutable propuesto de respaldo y restauración

> Regla exacta autorizada y reevaluación posterior: véase
> [compatibilidad CHECK v1 y resultado](e4-check-compatibility-results.md).
> El fallo inicial se conserva; no se repitió la restauración.

> Ensayo autorizado posterior: bwrap y aplicación SQL terminaron, pero la
> comparación estricta falló en una expresión CHECK. Instancia privada
> detenida y respaldo íntegro; no se acredita éxito completo. Véase
> [resultado real del ensayo](e4-restore-validation-results.md).

> Intento autorizado posterior (2026-11-09): **bloqueado antes de captura**
> porque sudo -n exigió autenticación interactiva. No se generó dump ni se
> ejecutó bwrap/restauración. Véanse [resultados reales](e4-backup-restore-results.md).
> El procedimiento siguiente se conserva; no es evidencia de ejecución exitosa.

Estado: 2026-11-09. **Preparado, no ejecutado. E.4 abierta.** Solo se hicieron
lecturas e inspección de herramientas. No se crearon dumps, roles, bases, instancias
ni namespaces; no sudo, restauración, parada, migración, despliegue o publicación.
Los comandos siguientes son una propuesta para autorización posterior; no una
instrucción de ejecutarlos como parte de esta revisión.

## 1. Herramientas, destinos y evidencia actual

- Binarios concretos: `/usr/lib/postgresql/18/bin/{pg_dump,pg_restore,psql,initdb,
  pg_ctl,postgres,createdb,pg_config}`: PostgreSQL **18.6**, paquete Ubuntu
  18.6-0ubuntu0.26.04.1. Los clientes `/usr/bin/pg_dump`, `pg_restore`, `psql` son
  entradas disponibles; se prefieren las rutas versionadas de abajo.
- `pg_lsclusters` real: únicamente 18/main, online, puerto 5432, dueño OS postgres,
  datos `/var/lib/postgresql/18/main`. TCP visible: 127.0.0.1:5432; socket
  `/var/run/postgresql/.s.PGSQL.5432`. No se identificó una instancia aislada
  utilizable; inventario no equivale a descartar todo servicio no registrado.
- OS actual: niereme UID/GID 1000. Existe postgres UID112/GID115. Pertenecer al grupo
  sudo no acredita permiso/autenticación administrativa: no se intentó sudo.
- Lectura nueva con conexión existente M, identidad/destino verificados, transacción
  REPEATABLE READ READ ONLY y ROLLBACK: blueflora_dev/public, head único
  0003_resource_permissions, dueño blueflora_dev, UTF8, proveedor libc (`c`),
  LC_COLLATE/LC_CTYPE en_US.UTF-8, versión de collation 2.43. Diez tablas conocidas.
  ACL de base confirmados: PUBLIC CONNECT/TEMPORARY, M CONNECT/CREATE/TEMPORARY y
  CONNECT explícito de blueflora_api, todos otorgados por M y sin grant option.
  Roles M/R sin settings, connlimit -1 y cero settings específicos de base.
  No se contaron datos privados ni se llamó al gateway. La ausencia de datos es
  antecedente del preflight; debe revalidarse al capturar.
- Acceso previsto al origen: operador ya autorizado como usuario OS postgres,
  socket local, rol SQL postgres, `-w` (sin pedir contraseña). Puede usar una sesión
  OS postgres ya existente o autorizar explícitamente `sudo -n -u postgres` de abajo.
  **Peer no está confirmado**: pg_hba.conf no es legible por niereme. Si falla el
  acceso no interactivo, detener; no cambiar pg_hba, contraseñas o privilegios.
- Aislamiento disponible: `/usr/bin/bwrap` 0.11.1; util-linux unshare/setpriv 2.41.3.
  userns_clone=1 y apparmor_restrict_unprivileged_userns=1. No se probó abrir un
  namespace; bwrap no es setuid y no se encontraron perfiles en las dos rutas
  `/etc/apparmor.d/{bwrap,bubblewrap}` inspeccionadas. No se certifica que pueda
  ejecutarse. Si se deniega, parar sin relajar AppArmor/sysctl ni ejecutar sin sandbox.
- No existen en las rutas propuestas los directorios privados de backup/restore.
  No se buscó contenido en respaldos externos ni se afirma disponer de copia válida.

### Artefactos de 0005

Están presentes y no ignorados, actualmente **untracked**, en el conjunto E.4:
0004_domain_revisions.py, 0005_mutation_gateway.py, 0005_mutation_gateway.sql,
0005_capability_query.sql y 0005_capability_manifest.json. No están preparados en
el índice ni publicados todavía. Deben incluirse explícitamente al preparar Git.
0005 carga sus auxiliares respecto de Path(__file__).parent, no del cwd.
La prueba `test_migration_artifacts_from_complete_clean_copy` copia migraciones e
ini a un árbol limpio, cambia cwd, migra una fixture y comprueba el manifiesto.
Pasó dentro de las **248 pruebas anteriores de R1**; no se repitió en esta tarea.
Esto acredita los auxiliares de migración copiados; no certifica un paquete wheel
ni un despliegue que omita el directorio migrations. No se probó un wheel.

Este documento concreta y sustituye los ejemplos anteriores de respaldo/restore
en e4-final-review-preflight.md y e4-r1-capabilities.md. Los roles equivalentes
propuestos aquí se crean solo dentro de la nueva instancia y requieren autorización.
No modifica la decisión de mantener intactos roles y permisos del clúster real.

## 2. Identidades y frontera de autorización

Origen: postgres SQL es el candidato existente con SUPERUSER/BYPASSRLS. Los roles
M/R no permiten garantizar pg_dump completo bajo FORCE RLS. No se les concede nada.
No hay alternativa completa acreditada con sus permisos actuales.

Ensayo recomendado: instancia privada bajo **niereme**, sin sudo ni instalación,
encerrada en bwrap con red/PID/IPC/UTS/user namespaces, sin repositorio, HOME,
credenciales ni sockets reales montados. Solo /usr, identidad OS mínima, dump de
entrada readonly y directorio privado de trabajo. PostgreSQL sin TCP, socket
`/work/socket`, puerto lógico 55433; datos `/work/data` dentro del sandbox.
No es blueflora_dev ni blueflora_test. No usar pg_createcluster ni servicios globales.

initdb requiere un rol de bootstrap LOGIN para abrir la primera conexión. Será
niereme, **sin contraseña**, únicamente peer dentro del socket privado. Antes de
leer el contenido restaurado, la sesión final ejecuta `ALTER ROLE niereme NOLOGIN`.
pg_restore genera primero un archivo SQL con BEGIN/COMMIT, sin conectarse.
Luego psql abre una sola sesión al destino: ejecuta NOLOGIN, incluye ese SQL y
recoge los inventarios. No se usa pg_restore --dbname después de NOLOGIN.
Esa conexión ya abierta permanece válida; todas las identidades, incluidas las
copias M/R, serán NOLOGIN durante la restauración. No se abre una conexión nueva
ni se ejecuta pg_dump del destino después. Evidencia y verificación se recogen en
esa misma sesión. Al terminar no queda ningún rol LOGIN. Este bootstrap transitorio
es imprescindible para usar clientes SQL normales; no se presenta como ausencia
de LOGIN desde el instante de initdb.

Los dos roles de origen se recrean **solo en la instancia nueva** con iguales nombres
y atributos relevantes, excepto LOGIN→NOLOGIN. Nunca se copian contraseñas,
password hashes, membresías ni roles globales del clúster real. No pg_dumpall --globals-only.
La creación de esas identidades y el cambio del bootstrap son nuevas acciones a
aprobar, no quedan autorizados por las pruebas R1.

Un dump de una base conserva objetos/owners y sus ACL, pero no crea roles globales,
no guarda sus membresías/contraseñas ni configura pg_hba. Sin --create tampoco
reproduce por sí solo propietario/ACL de la base contenedora. Aquí el operador
prepara una base nueva con OWNER blueflora_dev y replica su CONNECT explícito
para blueflora_api dentro de la instancia aislada. El inventario contrasta esos
ACL con el origen. Los dos roles se crean con atributos mínimos equivalentes y
NOLOGIN; el gate exige cero membresías/settings y connlimit -1 en el origen.
Si esos requisitos cambian, detener y revisar; no exportar ni modificar roles
reales automáticamente. No se acredita recuperación de la configuración global
del clúster ni de credenciales mediante este dump.

## 3. Captura futura: operador y comandos ordenados

Antes: identificar los escritores reales (API completo, auth, workers, cron,
importadores, SQL administrativo/catálogo) y asegurar ventana sin nuevos escritores.
La inspección no proporciona unidad de servicio/PID confirmado; no se inventa un
comando de parada. Autorizar esa coordinación aparte. Las consultas comprueban
actividad puntual, no impiden que un supervisor vuelva a conectar.

Los bloques 3–5 se ejecutarán como niereme, **solo tras autorización**, desde una
shell bash nueva. No reutilizar variables PG* de otra tarea.

### 3.1 Directorios, fuentes y consulta de comparación

```bash
set -euo pipefail
set -o noclobber
umask 077
BF_BIN=/usr/lib/postgresql/18/bin
BF_SRC=/home/niereme/Documents/Blueflorapp/backend
BF_NO_PASSFILE=/dev/blueflora-e4-no-password-file
# Ruta inexistente: no crear un archivo de contraseñas ni aceptar un enlace.
if [[ -e "$BF_NO_PASSFILE" || -L "$BF_NO_PASSFILE" ]]; then
 printf 'STOP: la ruta PGPASSFILE debe permanecer inexistente.\n' >&2
 exit 2
fi
BF_BASE=/home/niereme/.local/share/blueflora
mkdir -p -- "$BF_BASE/backups" "$BF_BASE/restore-e4"
chmod 700 -- "$BF_BASE" "$BF_BASE/backups" "$BF_BASE/restore-e4"
BF_CASE=$(mktemp -d "$BF_BASE/backups/e4-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXXXX")
BF_WORK=$(mktemp -d "$BF_BASE/restore-e4/run-XXXXXXXX")
export BF_CASE BF_WORK BF_SRC
sha256sum -- "$BF_SRC/migrations/versions/0004_domain_revisions.py" \
 "$BF_SRC/migrations/versions/0005_mutation_gateway.py" \
 "$BF_SRC/migrations/versions/0005_mutation_gateway.sql" \
 "$BF_SRC/migrations/versions/0005_capability_query.sql" \
 "$BF_SRC/migrations/versions/0005_capability_manifest.json" \
 "$BF_SRC/migrations/versions/0005_diameter_check_contract.json" > "$BF_CASE/sources.sha256"
```

Generar un inventario técnico autocontenido. **No** invoca resource_apply ni aprende
un contrato nuevo. Es una fotografía comparativa 0003, no readiness E.4. El dump
contendrá todo el esquema; estas verificaciones cubren los objetos actuales conocidos.
Si aparecen tablas, funciones, esquemas o identidades no esperados, detener/revisar.

```bash
python3 - <<'PY'
import os
from pathlib import Path
root=Path(os.environ['BF_SRC']); out=Path(os.environ['BF_CASE'])
q=(root/'migrations/versions/0005_capability_query.sql').read_text().strip().rstrip(';')
q=q.replace('__SCHEMA__','public').replace('__OWNER__','blueflora_dev').replace('__RUNTIME__','blueflora_api')
import json
rule=json.loads((root/'migrations/versions/0005_diameter_check_contract.json').read_text())
q=q.replace('__DIAMETER_CONTRACT__',json.dumps(rule,ensure_ascii=True))
names=['auth_rate_limits','auth_refresh_tokens','auth_sessions','gardens','growth_history','plants','species','users','watering_events']
counts=','.join("'%s',(SELECT count(*) FROM public.%s)"%(n,n) for n in names)
sql="""BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL TimeZone='UTC';
SELECT jsonb_build_object('catalog',("""+q+"""),
 'head',(SELECT jsonb_agg(version_num ORDER BY version_num) FROM public.alembic_version),
 'counts',jsonb_build_object("""+counts+"""),
 'database',(SELECT jsonb_build_object('owner',pg_get_userbyid(datdba),'encoding',pg_encoding_to_char(encoding),'provider',datlocprovider,'collate',datcollate,'ctype',datctype,'locale',datlocale,'collversion',datcollversion) FROM pg_database WHERE datname=current_database()),
 'functions',(SELECT coalesce(jsonb_agg(pg_get_functiondef(p.oid) ORDER BY p.proname,pg_get_function_identity_arguments(p.oid)),'[]'::jsonb) FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.prokind IN ('f','p')),
 'indexes',(SELECT coalesce(jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY c.relname),'[]'::jsonb) FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid WHERE t.relnamespace='public'::regnamespace),
 'tables',(SELECT jsonb_agg(relname ORDER BY relname) FROM pg_class WHERE relnamespace='public'::regnamespace AND relkind='r'),
 'schema_acl',(SELECT jsonb_agg(jsonb_build_array(CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,pg_get_userbyid(a.grantor),a.privilege_type,a.is_grantable) ORDER BY a.grantee=0,pg_get_userbyid(a.grantee),a.privilege_type) FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a WHERE n.nspname='public'),
 'database_acl',(SELECT jsonb_agg(jsonb_build_array(CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,pg_get_userbyid(a.grantor),a.privilege_type,a.is_grantable) ORDER BY a.grantee=0,pg_get_userbyid(a.grantee),a.privilege_type) FROM pg_database d CROSS JOIN LATERAL aclexplode(coalesce(d.datacl,acldefault('d',d.datdba))) a WHERE d.datname=current_database()),
 'role_configuration',(SELECT jsonb_object_agg(rolname,jsonb_build_array(rolconnlimit,rolconfig IS NULL)) FROM pg_roles WHERE rolname IN ('blueflora_dev','blueflora_api')),
 'database_settings_count',(SELECT count(*) FROM pg_db_role_setting WHERE setdatabase=(SELECT oid FROM pg_database WHERE datname=current_database())),
 'default_acl_count',(SELECT count(*) FROM pg_default_acl),
 'extra_schemas',(SELECT count(*) FROM pg_namespace WHERE nspname NOT LIKE 'pg_%' AND nspname NOT IN ('public','information_schema')),
 'extensions',(SELECT jsonb_agg(jsonb_build_array(extname,extversion) ORDER BY extname) FROM pg_extension));
ROLLBACK;
"""
(out/'inventory.sql').write_text(sql)
PY
```

### 3.2 Revalidación como postgres sin contraseña

La función siguiente contiene **sudo propuesto para el usuario**, no ejecutado
por Codex. Alternativa: operador abre su sesión OS postgres por el mecanismo ya
aprobado y usa el mismo psql sin sudo. En el paso B el operador puede introducir
personalmente su contraseña sudo en su terminal; nunca por chat. Estos bloques
interactivos no los ejecuta el agente ni este reutiliza la autenticación de otra
terminal. psql/pg_dump conservan -w: no pedir contraseña PostgreSQL ni usar fallback
TCP. Si falla sudo o la autenticación PostgreSQL, detener.

```bash
bf_source() {
 sudo -u postgres /usr/bin/env -i PATH="$BF_BIN:/usr/bin:/bin" \
  PGPASSFILE="$BF_NO_PASSFILE" PGSERVICEFILE=/dev/null \
  PGOPTIONS='-c default_transaction_read_only=on' \
  "$BF_BIN/psql" -X -w -h /var/run/postgresql -p 5432 -U postgres \
  -d blueflora_dev -v ON_ERROR_STOP=1 "$@"
}
cat > "$BF_CASE/gate.sql" <<'SQL'
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT current_database()='blueflora_dev' AND current_user='postgres'
 AND current_setting('transaction_read_only')='on'
 AND current_setting('server_version_num')::int/10000=18
 AND (SELECT rolsuper AND rolbypassrls FROM pg_roles WHERE rolname=current_user)
 AND (SELECT count(*)=1 AND min(version_num)='0003_resource_permissions' FROM public.alembic_version)
 AND NOT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid()) AS ready \gset
\if :ready
 SELECT 'destination/head/identity/no-other-sessions: OK';
\else
 \quit 3
\endif
ROLLBACK;
SQL
bf_source -Atq < "$BF_CASE/gate.sql" > "$BF_CASE/gate-before.txt"
bf_source -Atq < "$BF_CASE/inventory.sql" > "$BF_CASE/source-before.json"
df -Pk -- "$BF_BASE" > "$BF_CASE/disk-before.txt"
bf_source -Atq -c "SELECT pg_database_size(current_database())" > "$BF_CASE/database-size-bytes.txt"
```

Antes del dump, validar estrictamente los datos vacíos y la matriz conocida:

```bash
python3 - <<'PY'
import json,os
from pathlib import Path
x=json.loads((Path(os.environ['BF_CASE'])/'source-before.json').read_text())
assert x['head']==['0003_resource_permissions']
assert all(v==0 for v in x['counts'].values()), 'Datos cambiaron: revisar antes de capturar'
assert x['tables']==['alembic_version','auth_rate_limits','auth_refresh_tokens','auth_sessions','gardens','growth_history','plants','species','users','watering_events']
assert len(x['functions'])==7 and x['extensions']==[['plpgsql','1.0']]
assert x['extra_schemas']==x['default_acl_count']==x['database_settings_count']==0
assert x['role_configuration']=={'blueflora_dev':[-1,True],'blueflora_api':[-1,True]}
assert {f[0] for f in x['catalog']['functions']}=={'auth_access','auth_attempt','auth_logout','auth_lookup','auth_register','auth_rotate','auth_start_session'}
for table in x['catalog']['tables'].values():
 assert table['owner']=='M'
 assert all(a[0] in ('M','R','PUBLIC') for a in table['acl'])
 for column in table['columns']:
  assert all(a[0] in ('M','R','PUBLIC') for a in column['acl'])
 for policy in table['policies']:
  assert set(policy['roles'])<= {'M','R','PUBLIC'}
assert sorted(x['database_acl'])==sorted([
 ['PUBLIC','blueflora_dev','CONNECT',False],['PUBLIC','blueflora_dev','TEMPORARY',False],
 ['blueflora_api','blueflora_dev','CONNECT',False],['blueflora_dev','blueflora_dev','CONNECT',False],
 ['blueflora_dev','blueflora_dev','CREATE',False],['blueflora_dev','blueflora_dev','TEMPORARY',False]])
for label,inherit in [('M',True),('R',False)]:
 assert x['catalog']['roles'][label]==dict(login=True,super=False,bypass=False,inherit=inherit,createdb=False,createrole=False,memberships=0,replication=False)
assert x['database']==dict(owner='blueflora_dev',encoding='UTF8',provider='c',collate='en_US.UTF-8',ctype='en_US.UTF-8',locale=None,collversion='2.43')
print('Gate de contenido/configuración: OK')
PY
```

Si alguna condición cambió, no adaptar el script a ciegas. Revisión posterior para
roles/objetos/datos adicionales y definición de verificaciones de contenido.

### 3.3 Respaldo completo y evidencias

```bash
test ! -e "$BF_CASE/blueflora_dev.dump"
test ! -e "$BF_CASE/blueflora_dev.dump.partial"
sudo -u postgres /usr/bin/env -i PATH="$BF_BIN:/usr/bin:/bin" \
 PGPASSFILE="$BF_NO_PASSFILE" PGSERVICEFILE=/dev/null \
  PGOPTIONS='-c default_transaction_read_only=on' \
 "$BF_BIN/pg_dump" -w -h /var/run/postgresql -p 5432 -U postgres \
 --format=custom --lock-wait-timeout=10000 --dbname=blueflora_dev \
 > "$BF_CASE/blueflora_dev.dump.partial" 2> "$BF_CASE/dump.stderr"
mv -- "$BF_CASE/blueflora_dev.dump.partial" "$BF_CASE/blueflora_dev.dump"
sync -f "$BF_CASE/blueflora_dev.dump"
"$BF_BIN/pg_restore" --list "$BF_CASE/blueflora_dev.dump" > "$BF_CASE/toc.txt"
bf_source -Atq < "$BF_CASE/inventory.sql" > "$BF_CASE/source-after.json"
cmp -- "$BF_CASE/source-before.json" "$BF_CASE/source-after.json"
bf_source -Atq < "$BF_CASE/gate.sql" > "$BF_CASE/gate-after.txt"
(cd "$BF_CASE" && sha256sum -- blueflora_dev.dump inventory.sql source-before.json \
 source-after.json sources.sha256 toc.txt gate.sql gate-before.txt gate-after.txt disk-before.txt database-size-bytes.txt > SHA256SUMS)
chmod 600 -- "$BF_CASE"/*
(cd "$BF_CASE" && sha256sum --check SHA256SUMS)
sync -f "$BF_CASE"
```

Cualquier fallo aborta; `.partial` no es respaldo válido y no se renombra si pg_dump
falla. No borrarlo automáticamente: conservar diagnóstico privado y decidir luego.
Sin filtros de tablas/filas, --enable-row-security, --no-owner, --no-acl o desactivar
FORCE. El pg_dump usa su snapshot coherente; inventarios antes/después requieren
la ventana sin escritores, no comparten ese snapshot. Igualdad de inventarios y
cero sesiones son comprobaciones adicionales, no garantía contra un escritor
oculto que aparezca entre muestreos. Si no se puede asegurar la ventana, parar y
revisar un mecanismo de captura con snapshot exportado bajo autorización posterior.
No se cambia allow_connections ni se bloquean roles para fabricar la ventana.

El archivo custom incluye owners/ACL y todas las tablas, incluidas auth. No exporta
contraseñas de roles PostgreSQL. Una base poblada sí contendría hashes de usuarios
y tokens almacenados como datos necesarios para respaldo completo: no se omiten
silenciosamente ni se publican. El gate actual exige cero datos; si eso cambia,
se revisa protección/alcance antes de seguir. Inventarios solo contienen metadatos,
funciones del proyecto y recuentos; nunca filas, emails, tokens o payloads.
**TOC y SHA comprueban lectura/integridad del archivo, no su restaurabilidad.**

## 4. Instancia y restauración futuras sin sudo

Este bloque **crea y arranca una instancia**, por lo que requiere autorización nueva.
No existe todavía. No utilizar una simple instancia sin sandbox como fallback.
El namespace de red impide acceder a 127.0.0.1:5432 del host; no se monta su socket,
HOME, .env ni el repositorio. Los roles equivalentes y el GRANT CONNECT siguiente
existen exclusivamente dentro del clúster desechable. El GRANT reproduce el ACL
explícito real de la base, además de los CONNECT/TEMP de PUBLIC ya existentes.

```bash
# En la misma shell autorizada de 3, antes de iniciar el aislamiento:
printf 'niereme:x:1000:1000:BlueFlora restore:/work:/bin/bash\n' > "$BF_WORK/passwd"
printf 'niereme:x:1000:\n' > "$BF_WORK/group"
cat > "$BF_WORK/run.sh" <<'BASH'
set -euo pipefail
umask 077
BF_BIN=/usr/lib/postgresql/18/bin
mkdir -m 700 /work/socket /work/evidence
(cd /input && sha256sum --check SHA256SUMS) > /work/evidence/input-hashes.txt
"$BF_BIN/initdb" -D /work/data -U niereme --encoding=UTF8 \
 --locale-provider=libc --locale=en_US.UTF-8 \
 --auth-local=peer --auth-host=reject > /work/initdb.log 2>&1
cat >> /work/data/postgresql.conf <<'CONF'
listen_addresses = ''
port = 55433
unix_socket_directories = '/work/socket'
unix_socket_permissions = 0700
password_encryption = 'scram-sha-256'
fsync = on
full_page_writes = on
CONF
"$BF_BIN/pg_ctl" -D /work/data -l /work/postgres.log -w start
"$BF_BIN/psql" -X -w -h /work/socket -p 55433 -U niereme -d postgres \
 -v ON_ERROR_STOP=1 -q <<'SQL'
SELECT 1 / CASE WHEN current_user='niereme' AND current_database()='postgres'
 AND current_setting('data_directory')='/work/data'
 AND current_setting('port')='55433' AND current_setting('listen_addresses')=''
 THEN 1 ELSE 0 END;
CREATE ROLE blueflora_dev NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
 INHERIT NOREPLICATION NOBYPASSRLS CONNECTION LIMIT -1;
CREATE ROLE blueflora_api NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
 NOINHERIT NOREPLICATION NOBYPASSRLS CONNECTION LIMIT -1;
CREATE DATABASE blueflora_e4_restorecheck OWNER blueflora_dev TEMPLATE template0;
SET ROLE blueflora_dev;
GRANT CONNECT ON DATABASE blueflora_e4_restorecheck TO blueflora_api;
RESET ROLE;
SQL
# Generar SQL es lectura del archivo, aún no es restauración.
"$BF_BIN/pg_restore" --exit-on-error --single-transaction \
 --file=/work/restore.sql /input/blueflora_dev.dump
# Una única sesión final: cerrar LOGIN antes de ejecutar contenido restaurado.
"$BF_BIN/psql" -X -w -h /work/socket -p 55433 -U niereme \
 -d blueflora_e4_restorecheck -v ON_ERROR_STOP=1 -Atq > /work/evidence/session.txt 2> /work/evidence/session.stderr <<'SQL'
SELECT 1 / CASE WHEN current_database()='blueflora_e4_restorecheck'
 AND current_user='niereme' AND current_setting('data_directory')='/work/data'
 AND current_setting('listen_addresses')='' AND current_setting('port')='55433'
 THEN 1 ELSE 0 END;
ALTER ROLE niereme NOLOGIN;
SELECT 1 / CASE WHEN NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolcanlogin)
 AND NOT EXISTS(SELECT 1 FROM pg_authid WHERE rolpassword IS NOT NULL)
 THEN 1 ELSE 0 END;
\i /work/restore.sql
-- ON_ERROR_STOP + BEGIN/COMMIT generados: cualquier error de SQL es fatal.
SELECT 1 / CASE WHEN NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolcanlogin)
 AND NOT EXISTS(SELECT 1 FROM pg_authid WHERE rolpassword IS NOT NULL)
 THEN 1 ELSE 0 END;
\o /work/evidence/restore.inventory.json
\i /input/inventory.sql
\o
\echo Restore terminado; todos los roles NOLOGIN; inventario recogido.
SQL
# No se pueden abrir nuevas conexiones SQL: todos los roles son NOLOGIN.
# Detener exclusivamente la instancia /work/data del sandbox, nunca 18/main.
"$BF_BIN/pg_ctl" -D /work/data -m fast -w stop > /work/shutdown.log 2>&1
BASH
# No ejecutar run.sh directamente en el host; solo mediante este bwrap.
chmod 600 -- "$BF_WORK"/*
/usr/bin/bwrap --unshare-all --uid 1000 --gid 1000 --cap-drop ALL \
 --die-with-parent --new-session --clearenv \
 --ro-bind /usr /usr --symlink usr/bin /bin \
 --symlink usr/lib /lib --symlink usr/lib64 /lib64 \
 --dir /etc --ro-bind "$BF_WORK/passwd" /etc/passwd \
 --ro-bind "$BF_WORK/group" /etc/group \
 --proc /proc --dev /dev --tmpfs /tmp --dir /run \
 --bind "$BF_WORK" /work --ro-bind "$BF_CASE" /input --chdir /work \
 --setenv PATH /usr/lib/postgresql/18/bin:/usr/bin:/bin \
 --setenv LC_ALL en_US.UTF-8 --setenv TZ UTC \
 --setenv PGPASSFILE /dev/blueflora-e4-no-password-file --setenv PGSERVICEFILE /dev/null \
 /bin/bash /work/run.sh > "$BF_WORK/sandbox.stdout" 2> "$BF_WORK/sandbox.stderr"
```

Si bwrap está bloqueado, no arranca el script interior. Conservar el error técnico;
solicitar un entorno aislado aprobado (o revisión administrativa específica del
perfil userns), sin desactivar globalmente AppArmor ni instalar herramientas como
atajo. No se ha probado ese permiso en esta tarea. initdb/locale/libc también
pueden fallar; todos los pasos fallan cerrado. Si hay error después del arranque,
la salida del namespace PID termina sus procesos privados; no interpretar eso como
restauración correcta, no borrar datos/logs ni reiniciar para ocultar el fallo.
No hay acción sobre el servicio PostgreSQL real. Revisar disk-before.txt y
database-size-bytes.txt: el espacio disponible debe permitir dump + SQL expandido + PGDATA/WAL + evidencias, con margen; no basta el
tamaño comprimido. Aprobar capacidad antes de crear la instancia; no se midió capacidad para
cargas grandes.

## 5. Comparación y conservación futuras

Las comparaciones usan el mismo SQL de inventario, formato JSON y versión PG,
con expresiones/deparsers normalizados por search_path/TimeZone. No comparan OID
locales. El inventario incluye:

- Tablas/columnas/tipos/defaults; PK/UNIQUE/CHECK/NOT NULL/FK con relaciones
  compuestas, validación/diferibilidad; índices y definiciones completas.
- Funciones completas (pg_get_functiondef), propiedades/firmas/owners/search_path
  y ACL; RLS/FORCE, comandos/roles/USING/WITH CHECK de todas las políticas conocidas.
- ACL de esquema/base/tablas/columnas, PUBLIC y privilegios efectivos de R.
- Head y recuentos íntegros como superusuario, sin filtrado RLS ni lectura de filas
  hacia el informe; encoding/locale/collation y propietario de base.

Transformaciones cerradas previstas: M/R LOGIN=true en origen → false en
ensayo y la pareja exacta del CHECK de diámetro aprobada en
[compatibilidad exacta](e4-check-compatibility-results.md). Nombres/atributos restantes y todos los objetos/permisos deben coincidir.
El nombre de base de ensayo es distinto por diseño; se comprueba en el gate y no
se compara como si fuera el original. El bootstrap niereme solo existe en destino,
no participa en owners/ACL del proyecto y debe terminar NOLOGIN sin contraseña.

```bash
python3 -I - <<'PY_COMPARE'
import json,os,sys,hashlib
from pathlib import Path
sys.path.insert(0,os.environ['BF_SRC'])
from app.db.restore_comparison import compare_inventories
import app.db.restore_comparison as comparator
case=Path(os.environ['BF_CASE']); work=Path(os.environ['BF_WORK'])
inputs=[case/'source-after.json',work/'evidence/restore.inventory.json',work/'restore.sql']
a=json.loads(inputs[0].read_text()); b=json.loads(inputs[1].read_text())
proof=compare_inventories(a,b,legacy_ddl=inputs[2].read_text())
assert b['head']==['0003_resource_permissions']
assert all(n==0 for n in b['counts'].values())
proof['comparator_sha256']=hashlib.sha256(Path(comparator.__file__).read_bytes()).hexdigest()
proof['input_sha256']={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
# New result only: never replace the initial comparison, inventories or logs.
with (work/'evidence/reevaluation-bf-restore-inventory-v2.json').open('x') as f:
    json.dump(proof,f,indent=2)
print('MATCH: comparación corregida; no demuestra datos poblados ni PITR')
PY_COMPARE
(cd "$BF_CASE" && sha256sum --check SHA256SUMS)
# For a new reevaluation, preserve any earlier evidence manifest and use a new name.
(cd "$BF_WORK" && sha256sum -- evidence/reevaluation-bf-restore-inventory-v2.json \
 > reevaluation-bf-restore-inventory-v2.sha256)
(cd "$BF_WORK" && sha256sum --check reevaluation-bf-restore-inventory-v2.sha256)
```

No afirmar éxito si cualquiera de pg_dump, pg_restore, psql, parada privada o
comparación falla. Revisar también stderr y salida de procesos; ningún mensaje de
error debe quedar sin diagnosticar. No se llama a funciones auth_* ni al gateway
restaurados como prueba de lectura. Este ensayo restaura el head **0003**, no prueba
la migración E.4 ni readiness 0005 en desarrollo.

Si la sesión final se pierde después de NOLOGIN, no hay reconexión prevista:
el ensayo falla, se conserva evidencia y no se reactiva LOGIN ni se intenta reparar
automáticamente. Tras diagnosticar y obtener autorización, se podría repetir en
otra instancia nueva. No reutilizar el origen ni blueflora_test como destino.

Los roles NOLOGIN permiten contrastar derechos efectivos por catálogo; no probar
login SQL ni HTTP. Las credenciales del clúster real requieren su procedimiento
administrativo aparte, no se recuperan del dump de una sola base.

Una base vacía restaurada acredita estructura, funciones y permisos comprobados,
además de que el archivo se pudo aplicar. No demuestra recuperación de datos
poblados, UUID/fechas reales, semántica de autenticación, carga, rendimiento, PITR
ni escrituras posteriores al dump. Los ensayos poblados requieren autorización y
datos sintéticos separados, nunca fabricar datos en desarrollo para este trámite.

Conservar BF_CASE (dump original/hash/inventarios/TOC/fuentes) y BF_WORK (datos de
ensayo/SQL/logs/evidencias), directorios 0700 y archivos privados, fuera de Git.
No adjuntar dump, SQL de datos, directorio PGDATA ni logs privados a informes.
No incluir un rm automático; retención como mínimo hasta cierre y aceptación de
la migración, y después según decisión explícita del usuario. Una copia en el
mismo disco no cubre pérdida de ese disco: una segunda copia externa protegida
requiere destino y autorización propios. No se garantiza recuperación completa
posterior al dump; archivado WAL/PITR siguen sin habilitarse por este procedimiento.

## 6. Autorizaciones mínimas separadas y recomendación

| Grupo | Estado / autorización necesaria |
| --- | --- |
| Lecturas actuales, herramientas/versiones, Git y documentación | Permitidas y realizadas; sin suites ni compilaciones nuevas |
| Acceso OS/SQL postgres del origen | Usuario ejecuta desde sesión existente o autoriza comandos concretos sudo -n -u postgres; comprobar autenticación sin contraseña; sin cambios de pg_hba/roles |
| Ventana y ausencia de escritores | Identificar supervisor/procesos; parada/drenaje y prevención de reconexión requieren autorización posterior; no hay unidad confirmada |
| Captura | Autorizar directorios privados, lecturas completas, pg_dump y evidencia; no permisos nuevos de origen |
| Destino | Autorizar bwrap/user namespaces, creación initdb/instancia privada, roles NOLOGIN equivalentes, base nueva y su GRANT CONNECT, arranque y parada exclusivos del sandbox |
| Restauración/verificación | Autorizar generación/aplicación SQL del dump en ese destino, bootstrap NOLOGIN y comparación; sin acceso a bases reales desde sandbox |
| Si bwrap no puede aislar | Detener y obtener destino alternativo o revisión administrativa específica; no ampliar privilegios de M/R ni desactivar controles globales |
| Corte E.4 posterior | Nuevo preflight, parada real, migraciones 0004+0005/delta ACL, despliegue, arranque/humo y publicación Git: todos excluidos y requieren otra autorización |

Se recomienda la instancia temporal propiedad de niereme encerrada con bwrap,
condicionada a su disponibilidad efectiva: evita sudo adicional para **el ensayo**
y no modifica el clúster real. El respaldo del origen sí sigue necesitando al
operador postgres existente; no se ha encontrado una alternativa completa con los
permisos M/R. No pedir ni copiar su contraseña. Si no se acredita ese acceso o el
sandbox, el siguiente paso es resolver exactamente ese requisito, no migrar.

Git al preparar el procedimiento: main, HEAD
`af2bd84dadae3fba8a8fd8119c54a2307520cfa9`, índice vacío y cambios E.4 conservados.
Esta tarea modifica únicamente este documento y su enlace en e4-deployment.md.
.vscode/ sigue fuera. Sin commit, push, cierre E.4 ni fases posteriores.

## Revisión tras retomar la ejecución interrumpida

Se recuperaron este procedimiento y su enlace ya guardados. El último ajuste
documental anterior no llegó a ejecutarse por el límite de uso. Se completó ahora
sudo no interactivo (-n), la salida JSON del psql final (-Atq), la explicación de
la única sesión después de NOLOGIN y la distinción entre ACL de base y roles
globales. Solo revisión y comprobación estática Bash/Python; sin probar bwrap,
initdb, acceso postgres, dump ni restore. Las 248 pruebas R1 y la copia limpia de
migraciones siguen siendo evidencia anterior, no ejecuciones nuevas.

## Paso B preparado — ventana confirmada por el operador

El operador reportó para A `A_OK: blueflora_dev | postgres | READ ONLY |
PostgreSQL 18 | head 0003_resource_permissions`. Es un resultado comunicado por
el operador, no una nueva conexión del agente. El aviso de PGPASSFILE=/dev/null
no contradice ese A_OK: /dev/null no es archivo regular. Los comandos futuros
usan /dev/blueflora-e4-no-password-file, verifican que no exista y nunca lo crean.
Una ruta explícita inexistente evita leer el .pgpass predeterminado; -w impide
solicitar contraseña PostgreSQL. No se cambia autenticación.

**El operador confirmó la ventana en el chat.** La lectura posterior mostró cero
sesiones ajenas y ningún candidato activo. B se entrega reunido, con gates de
parada, en [paso B del operador](e4-operator-step-b.md); comprende únicamente las
secciones siguientes, ejecutadas personalmente en una terminal bash nueva:

1. Crear directorios únicos privados y generar el inventario técnico; no reutilizar
   rutas de capturas anteriores ni crear archivos de contraseñas.
2. Revalidar identidad/head/ausencia de otras sesiones, parámetros, roles/ACL,
   tablas y recuentos vacíos. Una sesión ajena, un dato o cualquier discrepancia
   detienen B; no borrar datos, cerrar conexiones ni cambiar condiciones.
3. Revisar disco disponible y tamaño de base antes de capturar. Debe quedar margen
   para dump, SQL expandido, PGDATA/WAL y evidencia. Si no puede acreditarse ese
   margen, detener antes del dump. Revalidar capacidad antes del ensayo posterior.
4. Ejecutar pg_dump completo con stderr privado y .partial; solo renombrar tras
   éxito. Error de sudo, PostgreSQL, dump o cualquier comando implica parada.
5. Generar TOC/hash, repetir inventario/gate, exigir igualdad y verificar SHA-256.
   No considerar TOC/hash como restauración probada. Conservar los artefactos y
   confirmar el resultado de B antes de que el agente inspeccione y continúe.

La confirmación debe abarcar API, workers, cron, clientes SQL y supervisores
conocidos, y el compromiso de no iniciarlos durante la captura. El muestreo sin
conexiones no la sustituye. Si hay un escritor activo se identifica primero el
proceso y su parada requiere autorización separada. La confirmación ya se recibió; los comandos siguen sin ejecutarse por el agente.
No se capturó nada ni se inició bwrap.
