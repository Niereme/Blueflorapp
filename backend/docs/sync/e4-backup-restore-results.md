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

# E.4 — intento autorizado de respaldo y restauración aislada

Estado: 2026-11-09. **BLOQUEADO antes de la captura. No hay respaldo ni restauración
nuevos. E.4 abierta; desarrollo sin modificaciones.**

El usuario autorizó ejecutar [el procedimiento revisado](e4-backup-restore-procedure.md),
con parada obligatoria si sudo -n/autenticación fallaban, sin probar alternativas.
Esta autorización no incluía detener escritores reales ni migrar/desplegar.

## Preparación realizada

Se leyeron AGENTS.md, transición, procedimiento completo y estado Git. Se conservaron
los cambios E.4/R1 y .vscode/. Índice vacío; main en
`af2bd84dadae3fba8a8fd8119c54a2307520cfa9`. No se repitieron suites ni builds.

Herramientas revalidadas: pg_dump, pg_restore, initdb y pg_ctl **18.6**, paquete
Ubuntu 18.6-0ubuntu0.26.04.1, rutas /usr/lib/postgresql/18/bin; bwrap **0.11.1**.
pg_lsclusters: 18/main online, dueño OS postgres, puerto 5432, datos
/var/lib/postgresql/18/main. No se inició un clúster adicional.

Disco revalidado en el volumen de /home/niereme/.local/share: **56 468 404 KiB
libres** (~53,85 GiB), uso 51%; /tmp: 7 787 140 KiB libres. Es una medición
preliminar, no la aprobación completa de capacidad: no se obtuvo el tamaño actual
de la base por el bloqueo y no se estimó el espacio de dump/SQL/PGDATA/WAL. No se
inició la captura o restauración con una estimación incompleta.

## Escritores y supervisores

Inspección de solo lectura de comm/cwd/PPid/cgroup de procesos accesibles, sin argv
ni entorno. Los procesos con cwd en el proyecto correspondían al editor, terminal,
Dart y herramientas de esta sesión; no se identificó un API/worker de BlueFlora
mediante esa inspección. No se paró ninguno.

Se inspeccionaron unidades/timers cargados de usuario y candidatos de sistema:
PostgreSQL 18/main y cron están activos; no apareció un servicio BlueFlora ni
supervisor API coincidente. No hay definiciones con nombre coincidente en
~/.config/systemd/user o /etc/systemd/system. crontab -l del usuario retornó 1 y
cero entradas en stdout. /etc/crontab y archivos inspeccionables de cron.d,
cron.hourly/daily/weekly/monthly no mostraron coincidencias de BlueFlora/servidores
Python buscados. No se imprimieron contenidos de tareas o credenciales.

**La ventana sin escritores NO quedó acreditada.** La inspección es limitada a
metadatos y tareas accesibles; no descarta supervisores con otro nombre/cwd,
crontabs de otros usuarios o clientes externos. No se obtuvo una nueva lectura de
pg_stat_activity y tampoco se usa ausencia de conexiones como garantía. Antes de
retomar se debe identificar/coordinar cualquier escritor y garantizar la ventana.
No se identificó un proceso concreto cuya parada deba proponerse; no se inventa
un nombre de servicio ni se solicita parar cron/PostgreSQL o el editor.

## Acceso al origen: fallo real

Se intentó únicamente el psql autorizado (sin pg_dump), con:

```bash
sudo -n -u postgres /usr/bin/env -i \
 PATH=/usr/lib/postgresql/18/bin:/usr/bin:/bin \
 PGPASSFILE=/dev/null PGSERVICEFILE=/dev/null \
 PGOPTIONS='-c default_transaction_read_only=on' \
 /usr/lib/postgresql/18/bin/psql -X -w \
 -h /var/run/postgresql -p 5432 -U postgres -d blueflora_dev \
 -v ON_ERROR_STOP=1 -Atq
```

La entrada preparada contenía BEGIN REPEATABLE READ READ ONLY, consultas técnicas
de identidad/head/tamaño/conexiones y ROLLBACK. **No llegó a ejecutarse psql**:
sudo terminó con código 1 y diagnóstico `interactive authentication is required`.
No hubo prompt, contraseña, reintento, mecanismo alternativo ni cambio de sudoers,
pg_hba, roles, membresías, contraseñas o permisos.

No se comprobó en esta ejecución la identidad SQL postgres, autenticación peer,
head/locale ni que el origen siga vacío. Head 0003, UTF8/en_US.UTF-8 y ACL del
procedimiento son comprobaciones anteriores, no observaciones SQL nuevas.
El fallo fue de sudo no interactivo, no de PostgreSQL ni de la revisión automática
de herramientas. Se respetó la condición de parada inmediatamente.

## Etapas no realizadas y artefactos

| Etapa | Resultado |
| --- | --- |
| Acceso SQL como postgres | No alcanzado; sudo falló antes |
| Ventana sin escritores | No acreditada; captura bloqueada |
| Directorios BF_CASE/BF_WORK de esta ejecución | No creados |
| Inventarios/source-before/gate como postgres | No generados |
| Dump/.partial/TOC/SHA-256/tamaño de respaldo | No generados; no existe hash o tamaño que informar |
| bwrap/aislamiento | No ejecutado; no demostrado ni fallido en esta ejecución |
| initdb, roles/base de ensayo, SQL/restauración | No ejecutados |
| Comparación de inventarios/NOLOGIN/contraseñas | No ejecutada |
| Parada de instancia privada | No aplicable: nunca se arrancó |
| Migración/despliegue de desarrollo | No ejecutados |

No hay captura fallida que reutilizar, ni archivos privados de respaldo nuevos,
ni logs/PGDATA/SQL de datos de este intento. No se sobrescribieron ni eliminaron
respaldos anteriores. Solo se creó este informe y se añadieron enlaces de estado
a la documentación. Los archivos E.4/R1 anteriores siguen conservados.

## Siguiente paso y autorizaciones

No recomendar aún la migración: falta acreditar acceso, ventana, captura completa
y restauración realmente verificada. Las 248 pruebas R1 anteriores no sustituyen
esas etapas. Tampoco se acredita recuperación de datos poblados, rendimiento o PITR.

El operador debe resolver **fuera de esta ejecución** el acceso no interactivo ya
previsto, o plantear para revisión otro mecanismo. No pedir contraseñas/tokens por
chat ni ampliar privilegios para sortear el bloqueo. Un cambio de mecanismo o de
política sudo requiere decisión explícita; no se prescribe un cambio de sudoers.
Después debe solicitarse retomar bajo las mismas comprobaciones, revalidando
ventana/destino/disco; no se continúa automáticamente tras el fallo. Si se descubre
un escritor activo, se identifica proceso/supervisor y comando concreto, y se
espera autorización independiente para su parada.

Solo después de un respaldo y ensayo completos podrá revisarse una autorización
posterior de migración. Sin commits/push, instalaciones, teléfono ni fases nuevas.

## Intervención del operador — paso A reportado

El usuario informó A_OK con identidad postgres, base blueflora_dev, READ ONLY,
PostgreSQL 18 y head 0003_resource_permissions. También comunicó el warning de
password file /dev/null no regular. No se reintentó sudo desde el agente ni se
aprovechó autenticación de la terminal del usuario. El bloqueo histórico anterior
se conserva; acceso A ahora acreditado por reporte del operador.

B se preparó con una ruta PGPASSFILE explícita inexistente (sin crear el archivo),
comandos sudo interactivos únicamente para el operador y las condiciones originales
de parada. **La ventana sigue pendiente de confirmación explícita**; no se creó
captura, inventario ni instancia en esta continuación. Desarrollo intacto.

## Ventana confirmada y B entregado al operador

El usuario confirmó no conocer API/workers/cron/clientes/supervisores activos y
no iniciar ninguno durante la captura. La lectura posterior mediante M existente,
REPEATABLE READ READ ONLY y ROLLBACK, mostró cero sesiones ajenas, head 0003 y
8468159 bytes de base. No se observaron procesos/supervisores candidatos. Disco:
56424780 KiB disponibles. Sin sudo del agente ni uso de autenticación ajena.

Se preparó [B reunido](e4-operator-step-b.md), incluido chequeo cuantitativo de
margen y gate de sesiones antes de pg_dump. Solo se generó un archivo de comandos
0600 en /tmp y documentación; no se ejecutó B ni se crearon sus directorios de
captura. El resultado real del respaldo sigue pendiente del operador. No hay
restauración ni migración nuevas.

## Resultado posterior: B verificado y ensayo aislado con comparación fallida

Se verificó B real (98161 bytes, SHA c2ba46963b76ab97bedcff73ba70272d468d4640c1a39c27f1a5bee2f24961be).
El ensayo bwrap autorizado aplicó el SQL y detuvo la instancia; la comparación
estricta detectó una diferencia CHECK no admitida. No hubo repetición ni cambio
de modo/LOGIN. Respaldo original íntegro y evidencia privada conservada. Véanse
[diagnóstico, parada y límites](e4-restore-validation-results.md). E.4 abierta;
no se recomienda migración antes de revisar ese hallazgo.
