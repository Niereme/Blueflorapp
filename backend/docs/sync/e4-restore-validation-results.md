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

# E.4 — ensayo bwrap: aplicación terminada, comparación estricta fallida

> Actualización autorizada 2026-11-10: ambas variantes exactas del CHECK se
> admiten de forma localizada. La reevaluación offline del ensayo conservado
> dio MATCH y mantiene el fallo inicial como evidencia histórica. Véase
> [compatibilidad y resultados](e4-check-compatibility-results.md). E.4 abierta.

Estado: 2026-11-09 (America/Mexico_City). **No se acredita el ensayo completo ni
se recomienda migrar. E.4 abierta.** Un único intento autorizado, sin repetición,
reconexión SQL tras NOLOGIN, reactivación LOGIN ni modalidad alternativa.

## Respaldo real verificado

El operador reportó B_OK y el agente verificó mediante lecturas los artefactos:

- Directorio: `/home/niereme/.local/share/blueflora/backups/e4-20261110T030212Z-7eRhcEbn`.
- Dump: `blueflora_dev.dump`, **98161 bytes**.
- SHA-256: `c2ba46963b76ab97bedcff73ba70272d468d4640c1a39c27f1a5bee2f24961be`.
- Directorios canónicos, dueño niereme, 0700; archivos regulares privados, sin
  permisos de grupo/otros. Destino de ensayo inicialmente vacío, sin PGDATA.
- SHA256SUMS íntegro, operator-result/status B_OK coherentes y source-before igual
  a source-after. Head único 0003_resource_permissions; diez tablas incluyendo
  alembic_version y cero filas en las nueve tablas de aplicación/auth.
- Disco previo al ensayo: 57776132096 bytes libres frente al margen exigido de
  2215228920 bytes (2 GiB + 8 × 8468159 bytes de base).

El respaldo original solo se leyó; su manifiesto y SHA se verificaron de nuevo
al finalizar. No se modificó ni se adjuntó dump, SQL de datos o inventarios privados.

## Aislamiento y ejecución reales

Destino nuevo: `/home/niereme/.local/share/blueflora/restore-e4/run-DJMNne0r`.
Se prepararon únicamente allí passwd/group mínimos y run.sh del procedimiento.
Se ejecutó una vez `/usr/bin/bwrap --unshare-all --uid 1000 --gid 1000 --cap-drop ALL`,
con PID/IPC/red/UTS/user namespaces, --die-with-parent, --new-session y entorno
limpio. Montajes: /usr readonly, enlaces de bibliotecas/binarios, identidad mínima,
proc/dev/tmp privados, /work escribible y /input (respaldo) readonly. Sin HOME,
repositorio, credenciales ni sockets originales montados. El script interior
**no se ejecutó directamente en el host**. bwrap no falló y terminó con código 0;
no se relajó AppArmor, namespaces ni ningún control del sistema.

Dentro: PostgreSQL 18.6, datos /work/data, socket /work/socket, puerto lógico 55433,
listen_addresses vacío; base blueflora_e4_restorecheck, distinta de desarrollo y
pruebas. Las comprobaciones SQL exigieron estos valores antes de aplicar contenido.
No hubo conexiones al origen ni a blueflora_test durante este ensayo.

Se crearon solo en ese clúster los roles equivalentes NOLOGIN y la base, con OWNER
blueflora_dev y CONNECT explícito de blueflora_api. pg_restore generó SQL con
--exit-on-error/--single-transaction, sin --no-owner ni --no-acl. La sesión psql
única abrió el destino, puso el bootstrap niereme en NOLOGIN, aplicó el SQL y
recogió inventarios con ON_ERROR_STOP. Las aserciones anteriores y posteriores
exigieron cero roles LOGIN y cero contraseñas no nulas en pg_authid; solo se
comprobaron esas condiciones, sin leer/imprimir hashes. Código 0, stderr vacío y
marcador final de sesión presente. No se invocó auth_* ni ninguna mutación restaurada.

## Comparación: fallo conservado, no excepción nueva

Inventario restaurado: 10 tablas, 7 funciones y 27 índices;
head 0003_resource_permissions y nueve recuentos de aplicación/auth iguales a cero.
Tras normalizar exclusivamente el LOGIN->NOLOGIN documentado de M/R, la comparación
completa falló. El diagnóstico recursivo encontró **una sola diferencia técnica**:

`catalog/tables/growth_history/constraints/1/expression`

Origen:

```sql
(((diameter_m IS NULL) AND (diameter_kind IS NULL)) OR ((diameter_m IS NOT NULL) AND (diameter_kind IS NOT NULL) AND ((diameter_kind)::text = ANY ((ARRAY['stem'::character varying, 'canopy'::character varying])::text[]))))
```

Restaurado:

```sql
(((diameter_m IS NULL) AND (diameter_kind IS NULL)) OR ((diameter_m IS NOT NULL) AND (diameter_kind IS NOT NULL) AND ((diameter_kind)::text = ANY (ARRAY[('stem'::character varying)::text, ('canopy'::character varying)::text]))))
```

La representación de casts del arreglo varchar/text difiere. Esto sugiere una
reconstrucción distinta de la expresión al aplicar el SQL de pg_dump; no se ha
probado equivalencia semántica arbitraria ni se acepta como diferencia permitida.
No se alteró el comparador, la restricción ni el manifiesto para obtener éxito.
Los demás elementos del inventario comparado coincidieron: tipos/defaults,
restantes constraints/relaciones, índices, funciones completas, owners, ACL,
RLS/FORCE/políticas, configuración, head y recuentos. Eso no convierte la
comparación global fallida en un ensayo aprobado.

Lectura estática adicional del manifiesto R1: la expresión de origen está incluida
(True) y la restaurada no
(False). Esto exige revisar la
compatibilidad entre restauración y contrato exacto R1 antes de avanzar. No se
instaló 0005 ni se ejecutó su gateway en el ensayo para probar esa consecuencia.

## Parada y evidencia

El bloque autorizado ya había detenido normalmente la instancia privada antes
de la comparación offline. Se verificó después con pg_controldata (salida 0):
**Database cluster state: shut down**, y ausencia de data/postmaster.pid.
No fue necesario reabrir una conexión SQL, parar el clúster real ni reactivar LOGIN.

initdb.log, postgres.log y shutdown.log: cero WARNING/ERROR/FATAL/PANIC buscados;
sandbox.stderr y evidence/session.stderr vacíos. No se imprimieron los logs.
El único fallo detectado fue la comparación exacta, no la generación/aplicación SQL.

Conservados, fuera de Git, sin borrado automático: PGDATA, restore.sql, run.sh,
logs, inventario restaurado, attempt-result.json y evidence/comparison-failure.json.
También evidence/shutdown-check.json y evidence-files.sha256, verificado con
salida 0. El campo exit de shutdown-check.json corresponde a la comprobación final
del manifiesto original; el diagnóstico del pg_controldata fue salida 0 y estado
shut down según el resultado capturado. No hay comparison.txt de éxito.

El dump original y su manifiesto siguen íntegros; sus SHA coinciden con B.
No se considera TOC/SHA como prueba de restauración completa.

## Límites y próximo paso

No repetir automáticamente ni corregir el esquema ensayado. Revisar con el usuario
la representación de esta restricción y el contrato exacto de capacidades R1,
y proponer una corrección/prueba específica antes de cambiar código o manifiestos.
Cualquier nuevo ensayo requiere revisión y autorización para otra instancia nueva.
**No recomendar todavía la migración de desarrollo.**

Origen vacío: aunque la aplicación SQL terminó, no acredita recuperación de datos
poblados, rendimiento, autenticación funcional ni PITR. Sin backups externos nuevos,
instalaciones, pruebas backend/Flutter, teléfono, migración 0004/0005 de desarrollo,
despliegue, commit/push o cierre E.4. Los roles/permisos del clúster real no cambiaron.

Git: main permanece en af2bd84dadae3fba8a8fd8119c54a2307520cfa9, índice vacío y
cambios anteriores conservados, incluida .vscode/. Esta tarea solo añade este
informe y notas/enlaces de resultados a la documentación existente.

## Diagnóstico posterior autorizado — 2026-11-10

[Diagnóstico focalizado y propuesta](e4-check-restore-diagnostic.md): nueve pruebas
aprobadas en blueflora_test reproducen el cambio de árbol al parsear el cast del
DDL emitido y la equivalencia específica de dos variantes. R1 rechaza actualmente
esa variante aunque mantenga tipos/propiedades/head. No se modificaron guardia,
comparador, manifiestos ni migraciones; el ensayo anterior sigue sin aprobar y
su clúster no se reinició. Hace falta autorización separada para cualquier corrección.
