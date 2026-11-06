# BlueFlora — Fase 3.2E.1: especificación de sincronización

Estado: **diseño normativo v1 propuesto para aprobación; no implementado**.
Fecha de revisión: 2026-11-06. Base inspeccionada: commit 32afa8b, contratos
3.2D y migraciones 0001_initial, 0002_auth, 0003_resource_permissions.
Nada en esta carpeta habilita rutas, tablas, dependencias ni permisos.

## Documentos y precedencia

1. [Protocolo HTTP y contratos JSON](protocol-v1.md): campos, límites, operaciones,
   recibos, errores, cursores, bootstrap e importación.
2. [SQLite, compatibilidad y migración](local-storage.md): esquema lógico cerrado,
   mapeo real Flutter/servidor, plataformas y recuperación.
3. [Seguridad, backend y plan](security-and-rollout.md): autorización, sesiones,
   cambios PostgreSQL/FastAPI/Flutter y decisiones de aprobación.
4. [Invariantes y matriz de pruebas](acceptance-tests.md): obligaciones verificables
   y puerta de entrada a 3.2E.2.

MUST/debe = obligación; SHOULD/recomendado = recomendación explícita. Ante dudas
no se adivina un valor ni se descartan datos: se bloquea solo el elemento afectado,
se conserva su original y se solicita resolución. Protocolo y esquema local son
versiones independientes. Cambiarlos requiere revisar esta especificación.
Los contratos actuales siguen descritos en [resources-api.md](../resources-api.md);
los campos y endpoints nuevos de estos documentos aún NO existen.

## Decisiones cerradas del protocolo v1

- SQLite es la fuente de datos de la interfaz. La conexión no condiciona el CRUD
  local; guardar entidad, evento y comando pendiente es una sola transacción.
- Identificadores estables; nunca deduplicar por nombre. Propietario derivado del
  token. Espacios separados por cuenta y servidor; anónimo no significa cuenta.
- Operaciones entregadas al menos una vez, con **efecto único** mediante recibos
  transaccionales. No se promete entrega de red exactamente una vez.
- Revisiones optimistas, comparación de base/local/remoto y conflictos duraderos.
  El reloj del dispositivo NO decide ganadores.
- Registro incremental por propietario, con grupos indivisibles y orden seguro
  de confirmación; ni offsets ni fechas históricas sirven de cursor.
- Tombstones de plantas y jardines; referencias históricas sin plantas ficticias.
- Bootstrap fijo y paginado; una reconstrucción conserva operaciones y conflictos.
- Importación voluntaria, validada, reanudable y con progreso explícito. No promete
  atomicidad de toda una importación: cada registro aplicado sí es atómico.
- Sin purga automática de recibos, tombstones o respaldos originales en v1.
- Perfiles de transporte cerrados: 50 operaciones/512 KiB por envío, páginas de
  hasta 100 grupos/1 MiB; recursos y grupos individuales acotados.

## Lo que existe y lo que falta

Ya existen UUID, repositorio local separado, controlador compartido, snapshot
plantas+eventos, eventos manuales UTC, transacciones servidor, RLS forzado,
roles separados y autenticación con refresh rotatorio. Solo plantas tienen
revision/updated_at/deleted_at. El REST actual no exige una revisión base.

Flutter no tiene modelos de jardines ni growth_history. Guarda Tree con nombres
españoles y especie libre; no se deben deserializar respuestas remotas directamente
como Tree ni enviar su JSON directamente al REST. No tiene cuentas, cola durable,
cursores ni tombstones. La eliminación local actual retira la planta y conserva
sus eventos. SharedPreferences contiene la clave trees como List<String>, con
un JSON PlantSnapshot schemaVersion=1, o formatos antiguos de lista de plantas.

Esta especificación conserva la regla de períodos de 86400 segundos, las unidades
en metros y el carácter declarado/manual del riego. No define humedad, hardware,
transferencia entre propietarios ni autenticación externa.

## Verificación de esta entrega

Solo se permiten cambios documentales bajo backend/docs. No ejecutar pruebas que
creen esquemas, migraciones, instalaciones o escrituras sobre datos del usuario.
La cifra anterior de 158 pruebas es el antecedente de 3.2D, no una nueva ejecución.
La validación documental deberá comprobar enlaces, JSON de ejemplo, sintaxis del
DDL ilustrativo en una base SQLite exclusivamente en memoria y consistencia de
los límites. No sustituye pruebas de Flutter, Android, seguridad o producción.
