# Seguridad, evolución de backend y plan de implementación

**Diseño de 3.2E.1, no cambios activos.** Separar aprobación del diseño de permiso
para instalar paquetes, ejecutar SQL, cambiar contratos públicos o desplegar.

## 1. Autenticación y acceso local

Los access tokens opacos actuales duran como máximo 15 minutos y las sesiones
30 días absolutos. PostgreSQL guarda hashes y la reutilización de un refresh
consumido revoca la sesión completa. No sustituirlo por JWT sin otra decisión.

Cada espacio de cuenta se vincula a (server_instance_id,user_id), ambos obtenidos
de respuesta autenticada /me bajo HTTPS y servidor elegido explícitamente. La URL
por sí sola no identifica la cuenta. No aceptar una identidad escrita en la cola
como prueba de autenticación. installation_id es distinto por espacio de cuenta.

Un vault del sistema guarda por espacio un único token_bundle versionado con
access_token, refresh_token, sujeto/instancia, token_generation y estado de refresh.
SQLite solo almacena referencias/estado no secreto. flutter_secure_storage es un
candidato, no dependencia instalada; verificar sus requisitos por plataforma y
versión antes de aprobarlo. No escribir tokens en SharedPreferences, reportes,
backups recuperables, import manifest ni crash reports.

Renovación:

1. Un solo coordinador/refresh en primer plano por cuenta. Prohibir workers de
   background y múltiples escritores hasta probar exclusión también entre procesos
   en escritorio. Ante imposibilidad de exclusión, no iniciar otra renovación.
2. Tras 401 de access, entrar al single-flight; guardar marcador de refresh incierto
   en vault ANTES de enviarlo. No congelar las ediciones locales mientras se espera.
3. Recibir pareja nueva y persistir TODO el bundle en una escritura segura; no
   guardar primero access y después refresh como si fueran independientes.
4. SQLite puede actualizar metadatos después: vault y SQLite no comparten COMMIT.
   Un desajuste de generación se resuelve conservadoramente, no usando refresh viejo.
5. Si se pierde la respuesta o se cierra la app entre rotación y almacenamiento,
   marcar needs_login/refresh_uncertain y pedir otra autenticación. No reintentar
   el refresh anterior automáticamente: podría revocar la sesión. Cola intacta.
6. Reintentar la operación sync original con el mismo operation_id al recuperar
   sesión; no duplicar un riego por renovar credenciales.

No fijar caducidad efectiva solo con expires_in=900: el vencimiento absoluto puede
ser anterior. /me/sync valida en servidor; el reloj local solo ayuda a anticipar
refresh, nunca autoriza ni resuelve conflictos. Respetar 429/Retry-After del backend.

### Bloqueo local y cambio de cuenta

- Anónimo siempre utilizable sin internet y sin cuenta; solo ese espacio visible
  cuando no existe uno de cuenta abierto expresamente.
- Una cuenta autenticada puede continuar leyendo/editando offline aunque expire
  su access, si mantiene una autorización LOCAL vigente y el espacio abierto.
  La autorización local NO permite enviar peticiones sin sesión de servidor válida.
- Después de logout o cambio de cuenta, bloquear el espacio anterior, incrementar
  auth_epoch, detener su worker y cancelar avisos. No mostrarlo en una lista que se
  pueda abrir sin comprobación. Para reabrir una cuenta cerrada en v1 se requiere
  reautenticación online al MISMO sujeto/instancia; no hay PIN offline propio.
- Para reanudar una cuenta no cerrada después de reinicio, se necesita el grant
  local del vault ligado a sujeto y auth_epoch, disponible bajo protección del SO.
  No basta un flag open en SQLite. Si el vault no está disponible, bloquear solo
  ese espacio, no borrar archivos y mantener modo anónimo.
- Un solo espacio activo; antes de cambiarlo, checkpoint local y auth_epoch nuevos.
  Toda petición captura espacio/época/sujeto/instancia; comprobarlos justo antes
  de enviar y antes de aplicar respuesta. Una respuesta tardía de A no entra en B.
- Si una escritura ya alcanzó el servidor al cerrar sesión puede estar confirmada
  en A. No prometer cancelación remota. Al reabrir A se recupera su recibo; nunca
  cambiarle el propietario para enviarla con B.
- Logout online intenta revocar y luego elimina bundle/grant; logout offline los
  elimina localmente sin prometer revocación remota inmediata. Las sesiones remotas
  siguen sus límites hasta revocación/expiración. Conservar siempre datos/outbox.

### Límite de la protección

SQLite en sandbox, espacios y vault evitan mezcla accidental y acceso por la UI
tras logout. **No cifran automáticamente plantas, conflictos o backups SQLite.**
La protección frente a copia del archivo, root o backups del SO requiere una
estrategia de cifrado y política de backup aprobadas aparte (incluyendo recovery).
No prometer esa garantía por instalar almacenamiento seguro de tokens. Propuesta
para E.2: validar primero persistencia anónima Android/Linux; no activar cuentas
reales ni migrar datos de cuentas cerradas hasta aprobar su protección. Web exige
además análisis XSS/almacenamiento del navegador: vault web no equivale a Keychain.

## 2. Vinculación voluntaria

Login/registro por sí solos NO suben datos. Flujo:

1. Identificar cuenta remota /me y obtener bootstrap, sin reemplazar el espacio
   anónimo. Mostrar cuenta/servidor elegidos y cantidades de plantas/historiales.
2. Selección explícita con eventos dependientes; advertir referencias históricas,
   fechas ambiguas, IDs inválidos, campos demasiado largos y planta de ejemplo.
3. Mostrar selección válida y exclusiones pendientes, sin seleccionar por nombre.
   Confirmación versionada link-local-v1. La persona puede cancelar sin subir nada.
4. Crear import_id, manifiesto, mapas y operaciones en una transacción local.
   Conservar backup del origen. Los elementos seleccionados pasan a un espacio
   de cuenta en estado pendiente de importación; no seguir editando simultáneamente
   dos copias vivas de la misma selección en anónimo y cuenta. Los no seleccionados
   permanecen anónimos. Export/respaldo anónimo de seleccionados queda recuperable.
5. Mientras se importa, nuevas ediciones locales forman operaciones dependientes
   que esperan confirmación de la creación/importación; no mutar el manifiesto
   ya enviado. Eventos nuevos se conservan aunque el import se bloquee.
6. Aplicar recibos por registro, no esperar que un fallo invalide todo lo aceptado.
   Cancelar no borra lo ya publicado; la UI muestra aplicados/pendientes. Mover de
   vuelta al espacio anónimo requiere acción explícita y no despublica el servidor.

Si el servidor ya tiene el mismo UUID propio, comparar contenido/revisión. No
fusionar por nombre ni sobrescribir diferencias. Copiar entre cuentas exige nueva
identidad y remapeo explícito de las referencias de esa COPIA; el original no cambia
de propietario. Esta función de copia no se implementa en sync v1.

## 3. Cambios PostgreSQL propuestos

No escribir ni ejecutar migraciones aquí. Se mantienen 0001–0003 inmutables.
Propuesta de futuras revisiones independientes y revisables:

### Estado de dominio

- gardens: revision BIGINT positiva, updated_at y deleted_at TIMESTAMPTZ; archivado.
  Conservar las asignaciones, sin DELETE físico ni desvinculación automática.
- plants: revision BIGINT; baseline_last_watered_at nullable y baseline_source.
  last_watered_at sigue siendo la proyección persistida, NO campo editable de sync.
- Backfill conservador: guardar el last_watered_at previo como baseline con fuente
  legacy_snapshot/server_pre_sync en metadatos; no inferir un evento ni fecha real
  de registro. No perder un valor actual aunque supere los eventos disponibles.
  baseline_source almacenado usa legacy_snapshot; server_pre_sync es procedencia
  de la migración, no un valor adicional del enum del protocolo.
- plant_identities: UUID global PK, owner_id, state full/historical_only y revisión;
  reserva identidades de plantas históricas sin fila plants. Referencias compuestas
  (owner_id,id) desde entidades/historiales. No inventar atributos ni deleted_at.
  Backfill debe detectar colisiones/inconsistencias existentes y detenerse para
  revisión, nunca apropiarse de una referencia de otro propietario.
- Eventos/mediciones conservan UUID y son inmutables; no hace falta updated_at
  editable: la secuencia del feed descubre inserciones tardías. Revisión protocolar
  "1" para hechos inmutables, incluso si no existe columna revision dedicada.
- Catálogo: versión global de snapshot; no se concede escritura a usuarios.
  En v1 no eliminar especies referenciadas mediante cambios administrativos que
  hagan SET NULL silencioso: cualquier modificación de relaciones debe pasar por
  el servicio de cambios por propietario. Las altas/ediciones descriptivas del
  catálogo actualizan catalog_version, sin sobrescribir species_label particular.

### Infraestructura de sincronización

| Tabla futura | Claves / contenido / reglas |
| --- | --- |
| client_installations | UUID, owner_id, protocolo, fechas; no credencial ni Raspberry Pi |
| sync_owner_state | owner_id PK, epoch, contador BIGINT; fila bloqueada en cada escritura |
| sync_operations | (owner_id,operation_id) único, instalación origen, fingerprint, resultado terminal, secuencia nullable |
| sync_change_groups | (owner_id,epoch,sequence) único, change_id, operation_id, imágenes acotadas; append-only |
| sync_bootstrap_sessions/items | owner+instalación, UUID/TTL, corte, payloads congelados, índice de página |
| sync_imports/records/requests | propietario, manifiesto/consentimiento, staging, hashes, estado, request receipts, progreso por índice |

Todo acceso privado lleva owner_id y FORCE RLS, USING y WITH CHECK por contexto
autenticado. Relaciones incluyen propietario; validar instalación de la misma
cuenta en cada llamada. No hace falta acceso de la API a hashes de autenticación.
Nuevas tablas requieren permisos explícitos aprobados, NO GRANT sobre tablas futuras.

La API necesita solo las operaciones necesarias por tabla: no otorgar DDL, DELETE
físico de plantas o escritura de especies. Archivado de jardines deja de necesitar
DELETE en ejecución: propuesta retirar ese permiso al activar el nuevo contrato.
La infraestructura append-only debe impedir reescrituras/borrados de recibos y
cambios por el rol API: funciones acotadas SECURITY DEFINER con propietario distinto,
search_path seguro, objetos cualificados y EXECUTE revocado a PUBLIC son la opción
recomendada. La lista exacta de firmas y GRANT se someterá a autorización antes
de implementar; no asumir que el permiso de 0003 cubre esta infraestructura.

### Orden transaccional

En cada mutación (REST o sync): autenticar/contexto → bloquear sync_owner_state →
recibo previo → bloqueos de entidades en orden estable → CAS/validaciones → datos →
contador → grupo → recibo → COMMIT. Mantener ese orden global para evitar deadlocks.
El servidor puede reintentar internamente deadlock/serialización con el MISMO
operation_id y comprobación del ledger; no emitir otro ID.

El contador por propietario es transaccional y su bloqueo dura hasta COMMIT, de
modo que otro dispositivo no observa secuencias posteriores dejando confirmaciones
anteriores invisibles. NO usar únicamente BIGSERIAL/nextval como orden de commit.
Una operación sin cambio nuevo recibe recibo pero no consume grupo; su
committed_sequence puede ser null. No usar updated_at como cursor: empates y reloj
no garantizan completitud. Filtros de UI nunca recortan el feed antes de persistir.

En v1 no purgar recibos/tombstones automáticamente. Retención compactada futura
requiere reglas explícitas de recibos, épocas y dispositivos desconectados. Una
restauración administrativa debe cambiar epoch y forzar bootstrap, sin descartar
colas de clientes. Un servidor restaurado que perdió ACK previamente emitidos
necesita reconciliación explícita; el diseño no promete recuperar datos perdidos
por restaurar una copia antigua sin backup/WAL adecuados.

## 4. Cambios FastAPI propuestos

- Mantener módulos y repositorios; agregar sync como orquestador, no segundo CRUD.
- Servicio común por mutación, CAS y ledger utilizado también por REST.
- DTO tagged-union por action, límites de cuerpo, validaciones y JCS verificables.
- Aplicación por operación/registro; recibo consultado antes de CAS y resultado
  terminal reproducible. No devolver éxito antes de COMMIT.
- Bootstrap materializado en una transacción de snapshot consistente, sin conexión
  viva entre páginas; TTL/cuotas y contexto de propietario.
- Importación exacta de nombres históricos/fechas seleccionadas y referencias
  históricas, sin permitir relaciones ajenas. Resolución de identidad mediante
  reserva global protegida; errores no revelan propietarios ni cuentas.
- Incorporar server_instance_id público a /me y las respuestas sync.
- Aprobar transición REST: ETag/If-Match, Idempotency-Key, archivado de jardines.
  Los tests anteriores se conservan en cobertura, adaptando explícitamente las
  expectativas de contrato; no crear un escritor antiguo que ignore CAS/feed.
- No exponer el rol de migración al proceso API. El rol de ejecución actual debe
  seguir sin propiedad, BYPASSRLS, CREATE ni pertenencia a roles privilegiados.
- Rate limits y cuotas sync distintos de la limitación de login: 60 POST sync/min
  y 120 GET sync/min por sujeto+instalación, más protección de tamaño/concurrencia.
  429 no borra ni confirma operaciones; Retry-After obligatorio. Ajustar estos
  límites requiere nueva versión/configuración documentada, no lógica de conflicto.

## 5. Cambios Flutter propuestos

- DAO/SQLite detrás del repositorio, interfaz local y controlador compartido.
- DTO de servidor separado de Tree y entidades locales; conservar campos remotos
  no editables desde la UI. No sobrecargar JSON legado como formato de transporte.
- Generar y persistir comandos con la modificación local; observador de conexión
  solo dispara intentos, no asegura que internet o el servidor estén disponibles.
- SyncCoordinator en primer plano, con exclusión por espacio, backoff, epochs y
  renovación single-flight. Nada de background/hardware en esta versión.
- UI: guardado local, pendiente, sincronizando, conflicto y error recuperable;
  nunca afirmar que un cambio local ya fue recibido por servidor.
- Pantallas de selección de vinculación, recuperación y conflictos antes de
  permitir sincronización automática. Mantener uso anónimo y datos tras logout.
- Recalcular resúmenes/avisos tras aplicar commits sin alterar periodos de 24 horas.
  Preferencias y avisos se quedan locales; IDs de notificación se separan por espacio.
- Evitar sobreescritura de fecha por reloj atrasado: proyección local de baseline
  y eventos, sin borrar el evento declarado ni sustituirlo por hora de recepción.

## 6. Orden y autorizaciones

| Subfase | Alcance | Puerta de salida |
| --- | --- | --- |
| 3.2E.1 actual | Documentación, contratos y matriz | Aprobación del diseño y decisiones abajo |
| 3.2E.2 | SQLite/DAO y migración ANÓNIMA, sin HTTP ni tokens | Migración/recuperación instrumentadas, datos iguales |
| 3.2E.3 | Cola durable, proyección y espacios | Cortes no pierden cambios ni mezclan cuentas |
| 3.2E.4 | Revisiones, ledger, feed y CAS REST | Migraciones/permisos aprobados; dos escritores seguros |
| 3.2E.5 | Sesiones móviles, consentimiento/importación | Tokens protegidos, errores/reintentos preservan datos |
| 3.2E.6 | Bootstrap/push/pull de dos dispositivos | Convergencia y tombstones sin pérdida |
| 3.2E.7 | Resolución de conflictos y fallos completos | Matriz de acceptance-tests satisfecha |

Decisiones que requieren aprobación explícita antes de su fase:

1. Dependencias/versiones SQLite, path, adaptadores FFI y vault; requisitos nativos
   Ubuntu y plataformas. No instalar apt/sudo ni modificar SDK automáticamente.
2. Validación inicial Android/Linux; estrategia y garantías para iOS/macOS/Windows
   y web. Web no recibe un fallback de menor durabilidad como si fuera equivalente.
3. Protección en reposo: aceptar sandbox+aislamiento lógico para la fase anónima,
   y decidir cifrado/backup antes de habilitar cuentas reales en la app.
4. Columnas, tablas, backfill y permisos futuros; verificar ausencia de colisiones.
5. Cambios deliberados del contrato REST y DELETE jardín → archivado.
6. Límites y política de retención v1, publicación parcial de importaciones con
   progreso, y reautenticación obligatoria ante refresh incierto.
7. UX de fechas/IDs incompatibles y comportamiento del ejemplo en primer arranque.

Aprobar 3.2E.2 NO autoriza todo lo anterior de una vez: solo SQLite/migración
anónima y dependencias expresamente aprobadas. Esta entrega no modifica código,
Flutter, .env, pruebas, bases, privilegios, commits ni GitHub.

Fuente de vault/plataformas: [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage).
Fuente de orden de transacciones/secuencias: [PostgreSQL](https://www.postgresql.org/docs/current/transaction-iso.html).
