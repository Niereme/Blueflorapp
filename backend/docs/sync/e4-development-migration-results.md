> **Cierre autorizado de 3.2E.4 — 2026-11-10.** Hito Git v0.3.5;
> creación de commit y publicación en origin/main autorizadas, publicación pendiente
> de comprobación. Se conservan las limitaciones documentadas. E.5 no iniciada ni
> autorizada. Los estados de preparación anteriores quedan como trazabilidad.

# E.4 — migración controlada de desarrollo

Fecha: 2026-11-10. **0004+0005 aplicadas; E.4 abierta, sin cierre Git ni despliegue persistente.**

## Revisión y condiciones satisfechas

main/HEAD af2bd84dadae3fba8a8fd8119c54a2307520cfa9, índice vacío; cambios previos y
.vscode/ conservados. 0001–0003 coinciden byte a byte con HEAD. Alcance E.4 servidor:
ocho escritores → mutate → ResourceRepository.apply → resource_apply; no queda
DML de recursos en repositorios/servicios Python. Auth conserva sus funciones.
Auxiliares SQL/JSON presentes y cargados respecto de __file__; el contrato exacto
bf-growth-diameter-exact-v1 conserva exclusivamente las dos expresiones autorizadas.
No se detectaron artefactos privados en el conjunto de entrega. Sin cambios de
código posteriores al log de las 292 pruebas anteriores; no se repitió la suite.
La única dependencia añadida en el diff E.4 continúa siendo rfc8785==0.1.4,
ya aprobada; esta ejecución no cambió dependencias, código ni migraciones.

El usuario renovó explícitamente la ventana sin escritores antes del corte.
Lecturas de procesos (sin argv/env), unidades y timers de sistema/usuario y
crontab propio no identificaron escritores/supervisores BlueFlora; ninguna entrada
en crontab propio y ningún proceso Python/uvicorn/gunicorn/celery/supervisor activo.
PostgreSQL y Apache del sistema no se detuvieron. No se presume que esa inspección
pruebe por sí sola ausencia absoluta de futuros escritores; se combina con la
confirmación del operador de no iniciarlos durante migración/comprobaciones.
Las puertas READ ONLY inicial e inmediata antes del upgrade encontraron cero
sesiones cliente adicionales en blueflora_dev. Espacio disponible: 57696776192 bytes.

## Respaldo vigente

Original conservado fuera del repositorio:
/home/niereme/.local/share/blueflora/backups/e4-20261110T030212Z-7eRhcEbn

blueflora_dev.dump: 98161 bytes; SHA-256
c2ba46963b76ab97bedcff73ba70272d468d4640c1a39c27f1a5bee2f24961be.
Tamaño/hash revalidados. El inventario completo actual, obtenido con el SQL
original conservado, coincide sin diferencias con source-after.json: objetos,
funciones, índices, políticas, restricciones, roles, permisos efectivos/ACL,
configuración, head y recuentos. No fue necesario nuevo dump/restauración.
Las transacciones de revalidación fueron REPEATABLE READ READ ONLY y ROLLBACK.
FORCE RLS permaneció activo; contexto auth_internal existente de M solo para
lectura/enumeración. users=0 comprobado bajo su política interna: no existen
owners ocultos que invaliden los recuentos vacíos dependientes por FK.

## Ejecución y transacción

Destino verificado: blueflora_dev.public, usuario SQL blueflora_dev; servidor
PostgreSQL 18.6 local, conexión existente validada por verify_database. Nunca se
usó postgres ni blueflora_api para migrar. Head previo único 0003_resource_permissions.

Comando realmente ejecutado desde backend/:

```bash
.venv/bin/python -m alembic -x database=development upgrade 0005_mutation_gateway
```

Resultado: salida 0, log sin contenido ni errores. env.py abre engine.begin()
externo, verifica destino, fija search_path local y ejecuta ambos upgrades dentro
de esa única transacción; sin autocommit ni COMMIT interno. Confirmación normal
y head final observados desde conexiones nuevas. No hubo fallo/COMMIT incierto,
rollback reparador, downgrade, restauración o regrants. Solo delta aprobado
0004_domain_revisions + 0005_mutation_gateway; sin cambios de atributos,
membresías, contraseñas o herramientas. Ningún escritor funcional se ejecutó.

## Comprobaciones nuevas posteriores, exclusivamente READ ONLY

- Head único: 0005_mutation_gateway. Catorce tablas, incluidas alembic y cuatro nuevas.
- users, species, gardens, plants, growth_history, watering_events, auth_sessions,
  auth_refresh_tokens y auth_rate_limits: **0 antes y después**.
- plant_identities, sync_owner_state, sync_operations, sync_change_groups: **0**.
  Backfill vacío legítimo; no identidades, recibos ni grupos históricos inventados.
- Catálogo completo de capacidades exactamente igual a 0005_capability_manifest.json:
  tablas/columnas/tipos/defaults, PK/UNIQUE/FK compuestas y CHECK, índices,
  ENABLE/FORCE RLS, políticas USING/WITH CHECK/comandos/roles, propietarios,
  gateway SECURITY DEFINER/search_path/firma, privilegios efectivos y de columna,
  PUBLIC y triggers/funciones de inmutabilidad. Capacidad diameter_check_contract=true.
- Cero constraints no validadas o no enforced. Recuentos vacíos: no relaciones,
  fechas/revisiones incompatibles ni filas que reconciliar; no prueba de backfill poblado.
- Runtime SELECT de recursos sin DML directo ni lectura de las cuatro tablas privadas;
  comprobado por catálogos, sin intentar INSERT/UPDATE/DELETE en desarrollo.
- Roles y sus atributos/membresías/configuración, ACL de base/esquema y las siete
  definiciones auth originales conservados exactamente. Ninguna función auth invocada.
- Guardia ResourceRepository.verify_schema aceptada como blueflora_api en READ ONLY.
  resource_apply(NULL,NULL) devuelve {"ready":true,"manifest":"e4-r1-pg18"}; solo
  variante técnica, no mutación ni sesión de autenticación.

## Readiness temporal y parada

Proceso Python local temporal, create_app() + lifespan/TestClient, sin socket
escuchando ni servicio registrado. Engine API configurado con transacciones
postgresql_readonly=True. Lifespan/readiness correcto, GET /health/live → 200/ok.
Contexto lifespan cerrado, engine.dispose() ejecutado y proceso terminó con salida 0.
No se levantó Uvicorn persistente ni hubo exposición externa. CRUD HTTP y
entrega de notificaciones no comprobados en desarrollo.

Aviso observado: StarletteDeprecationWarning al importar TestClient por uso de httpx;
no afectó al resultado y no se instalaron/actualizaron dependencias para ocultarlo.
Los primeros intentos de inspección de procesos/systemd dentro del sandbox no
permitían observar el host; se repitieron solo esas lecturas con acceso autorizado.

Evidencia técnica de esta ejecución, fuera de Git: /tmp/bf-e4-dev-current-inventory.json,
/tmp/bf-e4-dev-migration.log, /tmp/bf-e4-dev-post-inventory.json,
/tmp/bf-e4-dev-post-results.json y /tmp/bf-e4-dev-readiness.json.
Scripts de comprobación /tmp/bf_e4_dev_read.py, bf_e4_dev_post.py,
bf_e4_dev_readiness.py; no contienen credenciales. /tmp no es almacenamiento durable
para recuperación; el respaldo y la evidencia de restauración originales siguen en
las rutas privadas conservadas, sin alteraciones.

## Límites y revisión siguiente

Las 292 pruebas son evidencia aislada anterior, no ejecuciones nuevas en desarrollo.
Las comprobaciones nuevas son las lecturas de este informe, upgrade real y lifespan.
El origen vacío no acredita recuperación/backfill de datos poblados, rendimiento,
PITR o resiliencia física. El respaldo corresponde a 0003; no restaurarlo sobre
operaciones nuevas ni usarlo como downgrade. Cualquier problema posterior al COMMIT
requiere conservar datos, mantener escritores cerrados y corregir hacia delante.

Recomendación: pasar a revisión de cierre documental/Git, con autorización específica
antes de preparar/publicar un commit o activar un servicio. No se declara cerrada
E.4; sin despliegue persistente, commit/push/tags, Flutter/teléfono ni inicio de E.5.
