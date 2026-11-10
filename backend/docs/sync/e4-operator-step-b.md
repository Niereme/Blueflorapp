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

# E.4 — paso B del operador: captura, sin restauración

Preparado, **no ejecutado**. El operador reportó A_OK y confirmó que no conoce
escritores/supervisores activos y que no los iniciará durante la captura.
La comprobación nueva del agente, por la conexión existente M en READ ONLY,
mostró head 0003, cero sesiones ajenas y database_bytes=8468159. No se observaron
procesos/supervisores candidatos. Disponible: 56424780 KiB (~53,8 GiB).
Eso complementa la confirmación, no excluye por sí solo escritores futuros.

Este script reúne las secciones 3.1–3.3 del procedimiento revisado. Ejecuta sudo
interactivo únicamente en la terminal del operador; el agente no lo ejecutó ni
reutiliza credenciales de otra terminal. No crea contraseñas. La ruta PGPASSFILE
inexistente se verifica antes de las llamadas. Todos los fallos detienen B; no se
reanuda un intento fallido. Solo se renombra .partial después de pg_dump exitoso.

Se concreta el margen de disco en **2 GiB + 8 × tamaño de base**, comprobado antes
del dump para dump, SQL, PGDATA/WAL y evidencia; se revalidará antes de restaurar.
Se añade un gate de sesiones inmediatamente antes del dump. No se cambian origen,
head, exigencia de datos vacíos, ACL, propietarios ni autenticación.

Artefacto preparado para esta sesión: `/tmp/blueflora-e4-step-b-lz13_pra.sh` (0600).
SHA-256 del script: `e7cc27fe70a6145107c616d57b35ef233d14636d8ed71b2ee1fa757d565e168e`.
Es un archivo de comandos preparado, no un dump ni una captura fallida. La copia
a continuación permite revisar exactamente su contenido. Si /tmp desaparece,
no ejecutar otra versión ni extraer código automáticamente sin revisarlo.

Ejecutar personalmente en una terminal local, sin anteponer sudo a bash:

```bash
bash /tmp/blueflora-e4-step-b-lz13_pra.sh
```

No ejecutar si se inició algún escritor o se perdió la ventana. El éxito final
es `B_OK` más el JSON de directorios, tamaño y SHA; aun así la restauración sigue
pendiente. Ante fallo, detener y conservar las rutas impresas. No pegar logs,
inventarios, SQL ni datos privados en el chat. Confirmar resultado antes del ensayo.
No hay bwrap/initdb/migraciones/roles/paradas en este script.

```bash
#!/bin/bash
# Paso B: SOLO captura del origen; ejecutar personalmente como niereme.
set -Eeuo pipefail
set -o noclobber
umask 077
if [[ $(id -un) != niereme || ! -t 0 ]]; then
 printf 'STOP: ejecutar como niereme desde una terminal local interactiva.\n' >&2
 exit 2
fi
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
BF_STAGE=preparacion
trap 'rc=$?; printf "B_FALLO rc=%s etapa=%s; conservar %s y %s\n" "$rc" "$BF_STAGE" "$BF_CASE" "$BF_WORK" >&2; printf "FALLO rc=%s etapa=%s\n" "$rc" "$BF_STAGE" >> "$BF_CASE/status.log"; exit "$rc"' ERR
printf 'Ventana confirmada por operador en el chat; revalidar sesiones antes de captura.\n' > "$BF_CASE/window-confirmation.txt"
sha256sum -- "$BF_SRC/migrations/versions/0004_domain_revisions.py" \
 "$BF_SRC/migrations/versions/0005_mutation_gateway.py" \
 "$BF_SRC/migrations/versions/0005_mutation_gateway.sql" \
 "$BF_SRC/migrations/versions/0005_capability_query.sql" \
 "$BF_SRC/migrations/versions/0005_capability_manifest.json" > "$BF_CASE/sources.sha256"

python3 -I - <<'PY'
import os
from pathlib import Path
root=Path(os.environ['BF_SRC']); out=Path(os.environ['BF_CASE'])
q=(root/'migrations/versions/0005_capability_query.sql').read_text().strip().rstrip(';')
q=q.replace('__SCHEMA__','public').replace('__OWNER__','blueflora_dev').replace('__RUNTIME__','blueflora_api')
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

bf_source() {
 if [[ -e "$BF_NO_PASSFILE" || -L "$BF_NO_PASSFILE" ]]; then
  printf 'STOP: ruta PGPASSFILE inesperada.\n' >&2
  return 2
 fi
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

python3 -I - <<'PY'
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

BF_STAGE=disco_y_gate_inmediato
python3 -I - <<'PY_DISK'
import os,shutil
from pathlib import Path
case=Path(os.environ['BF_CASE']); work=Path(os.environ['BF_WORK'])
size=int((case/'database-size-bytes.txt').read_text().strip())
required=2*1024**3+8*size
free=min(shutil.disk_usage(case).free,shutil.disk_usage(work).free)
if free<required:raise SystemExit('STOP: margen insuficiente para dump/SQL/PGDATA/WAL/evidencias')
(case/'disk-gate.txt').write_text(f'database_bytes={size} required_bytes={required} available_bytes={free}\n')
print('Gate de disco: OK')
PY_DISK
bf_source -Atq < "$BF_CASE/gate.sql" > "$BF_CASE/gate-immediate-before-dump.txt"
if [[ -e "$BF_NO_PASSFILE" || -L "$BF_NO_PASSFILE" ]]; then exit 2; fi
BF_STAGE=pg_dump
test ! -e "$BF_CASE/blueflora_dev.dump"
test ! -e "$BF_CASE/blueflora_dev.dump.partial"
sudo -u postgres /usr/bin/env -i PATH="$BF_BIN:/usr/bin:/bin" \
 PGPASSFILE="$BF_NO_PASSFILE" PGSERVICEFILE=/dev/null \
  PGOPTIONS='-c default_transaction_read_only=on' \
 "$BF_BIN/pg_dump" -w -h /var/run/postgresql -p 5432 -U postgres \
 --format=custom --lock-wait-timeout=10000 --dbname=blueflora_dev \
 > "$BF_CASE/blueflora_dev.dump.partial" 2> "$BF_CASE/dump.stderr"
BF_STAGE=verificaciones_posteriores
mv -- "$BF_CASE/blueflora_dev.dump.partial" "$BF_CASE/blueflora_dev.dump"
sync -f "$BF_CASE/blueflora_dev.dump"
"$BF_BIN/pg_restore" --list "$BF_CASE/blueflora_dev.dump" > "$BF_CASE/toc.txt"
bf_source -Atq < "$BF_CASE/inventory.sql" > "$BF_CASE/source-after.json"
cmp -- "$BF_CASE/source-before.json" "$BF_CASE/source-after.json"
bf_source -Atq < "$BF_CASE/gate.sql" > "$BF_CASE/gate-after.txt"
(cd "$BF_CASE" && sha256sum -- blueflora_dev.dump inventory.sql source-before.json \
 source-after.json sources.sha256 toc.txt gate.sql gate-before.txt gate-after.txt disk-before.txt database-size-bytes.txt disk-gate.txt gate-immediate-before-dump.txt window-confirmation.txt > SHA256SUMS)
chmod 600 -- "$BF_CASE"/*
(cd "$BF_CASE" && sha256sum --check SHA256SUMS)
sync -f "$BF_CASE"

BF_STAGE=final
python3 -I - <<'PY_RESULT'
import hashlib,json,os
from pathlib import Path
case=Path(os.environ['BF_CASE']); work=Path(os.environ['BF_WORK'])
dump=case/'blueflora_dev.dump'
with dump.open('rb') as stream:
 fingerprint=hashlib.file_digest(stream,'sha256').hexdigest()
result={'backup_directory':str(case),'restore_work_directory':str(work),'dump_bytes':dump.stat().st_size,'sha256':fingerprint,'restoration':'pending'}
with (case/'operator-result.json').open('x') as stream:json.dump(result,stream,indent=2)
print('B_OK: captura e inventarios verificados; restauracion pendiente')
print(json.dumps(result))
PY_RESULT
printf 'B_OK; restauracion pendiente\n' >> "$BF_CASE/status.log"
sync -f "$BF_CASE"
```
