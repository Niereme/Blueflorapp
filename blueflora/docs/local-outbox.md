# Persistencia local E.3 — SQLite físico v2

Implementación local A/B/C y validación física Android completadas.
Cierre de E.3 autorizado por el usuario el 2026-11-07 como hito Git v0.3.4.
No se crean tags ni se cambian versiones internas.
E.2 permanece cerrada. E.4 no está iniciada ni autorizada.
Ver [resultados físicos E.3](android-outbox-validation-results.md).
No hay HTTP, cuentas, tokens, workers, sincronización ni acciones de hardware.

## Activación y migración

La fábrica Android abre `blueflora_anonymous_v1.sqlite` con `user_version=2`.
El nombre/ruta no cambia. Se conserva `database_id` y el archivo activation-guard.
Otros destinos continúan en SharedPreferences: soporte FFI no habilita Linux.
Se mantiene FK ON, journal DELETE, synchronous FULL y busy_timeout 5000 ms.

A/B/C se activan juntos: apertura v2, contrato de intenciones y proyección.
`onUpgrade(1,2)` corre en la transacción de apertura de sqflite. Reconstruye
local_spaces, referencias, plantas y eventos para retirar el CHECK del ID fijo
sin retirar kind=anonymous. Compara todas las columnas anteriores y sus filas
ordenadas antes de retirar las tablas candidatas v1. Añade metadatos y verifica
integrity_check/foreign_key_check. Un fallo revierte esquema, datos y user_version.
No cambia revisión global, activación, inicialización, source_hash, respaldos,
mapas ni diagnósticos E.2. No elimina filas de plantas borradas o eventos huérfanos.

Una base v1 activa incorpora sus filas y marca e3_ready en la misma transacción.
Una base nueva o con migración E.2 pendiente queda e3_ready=0 hasta incorporar el
origen mediante la ruta interna E.2: respaldo, mapa, escritura, captura, verificación
y activación juntos. Ausente continúa distinto de vacío. La primera planta demo
se crea a través de una intención, sin inventar un evento. Tras activación no hay
fallback a preferencias, ni base vacía ante corrupción, desaparición o identidad
incorrecta. El respaldo interno sigue sin proteger contra pérdida del dispositivo.

## Tablas y columnas utilizadas

Las siete tablas E.2 permanecen. local_spaces añade next_local_sequence INTEGER
positivo. storage_state añade e3_ready (0/1). plants/watering_events añaden
local_version INTEGER positivo, comenzando en 1 como versión de incorporación,
no como número de ediciones históricas. plants añade baseline_text, baseline_kind,
baseline_source (unknown/legacy_snapshot/declared_initial) y projection_mode
(comparable/legacy_hold). deleted, position y el tipo manual_registration se conservan.

Cuatro tablas nuevas:

- prior_state_records: PK (space_id,record_kind,record_id), source_kind,
  capture_version=1, source_revision, source_hash opcional, row_json y sha256.
- outbox: PK (space_id,operation_id), entity_type/entity_id, plant_ref_id,
  action, local_sequence única por espacio, entity_local_version, intent_json,
  request_sha256, result_json y status restringido a local_only.
- outbox_dependencies: PK (space_id,operation_id,depends_on), FK compuestas a
  outbox. Trigger exige secuencia de predecesor menor: sin ciclos ni autoaristas.
- local_diagnostics: PK (space_id,plant_id,code,operation_id), detail_json y FK
  compuesta a referencia de planta. operation_id vacío identifica incorporación.

Triggers impiden UPDATE/DELETE en capturas, outbox, dependencias y eventos.
No hay compactación ni purga. JSON validado en Dart, sin JSON1/STRICT.
El hash es SHA-256 de UTF-8 y no cifra ni autentica frente a manipulación forense.

## Estado previo, fuera del outbox

Captura una fila completa por referencia, planta activa/eliminada y evento,
incluidos huérfanos; sin planta artificial. Conserva las columnas E.2, sus textos,
orden y marcas. Excluye los metadatos nuevos v2 de esa imagen de origen.
source_kind=sqlite_v1 identifica actualización de una base activa;
preferences_import identifica incorporación del origen respaldado E.2.
source_revision es el contador encontrado; no una fecha original inventada.
source_hash enlaza el respaldo cuando existe; puede ser NULL en una base sin él.

Las capturas son datos encontrados, no plant.create ni watering_event.append.
No tienen operation_id ni fecha de intención. Se confirma toda la incorporación
o ninguna, y la apertura posterior no la repite. El envelope E.2 conserva además
la representación cruda del origen de preferencias, anterior a la normalización.

Adaptación aprobada de E.1 §5: no fabricar comandos local_only para ese estado
previo. Una futura vinculación necesitará consentimiento y operaciones de import
nuevas; ni capturas ni outbox anónimo se convertirán automáticamente en enviables.

## Intenciones y confirmación local

LocalMutation genera operation_id UUID v4 una sola vez. Guarda payload serializado
e inmutable, espacio, acción, identidad y revisiones esperadas. identityJson usa
un formato LOCAL versionado con claves ordenadas; no es JCS ni un DTO sync.
Modificar el mapa original o un mapa obtenido del getter no cambia la intención.

Acciones: plant.create, plant.update (solo campos de perfil modificados),
plant.delete y watering_event.append. El riego tiene UUID propio, instante UTC y
nombre histórico fijados. declarationText conserva adicionalmente la representación
del reloj del controlador para compatibilidad de SharedPreferences, sin sustituir
el instante del evento. No representa confirmación física de agua.

Dentro de una transacción: buscar primero operación confirmada; comparar texto
completo y hash; comprobar preparación y revisión global; comprobar versión de
planta; modificar planta/evento; insertar comando; enlazar predecesor de la misma
planta; avanzar secuencia y revisión. Confirmar todo o revertir todo. Solo después
se publica la proyección en memoria. SQLite rechaza save(snapshot); _write es una
ruta privada exclusiva de incorporación, no una vía de mutación ordinaria.

result_json guarda revisión confirmada, versión de planta, evento y secuencia.
El ID de operación está en la PK. Un COMMIT cuya respuesta se pierde se reconoce
por esa fila antes de comprobar revisiones antiguas. Un reintento confirmado carga
la vista vigente y no reaplica la intención ni publica un snapshot histórico.
Mismo ID/contenido diferente produce operation_id_reused explícito.

El controlador retiene la intención fallida. Un toque de riego sobre la misma
planta reintenta ese objeto; otras acciones quedan bloqueadas hasta confirmarlo.
Una acción deliberada posterior genera nuevo ID, aunque tenga el mismo instante.
Una intención que nunca llegó al COMMIT no se promete recuperable tras matar el
proceso. Después de COMMIT se recuperan comando y datos juntos.

## Concurrencia y espacios

storage_state.revision es global a la base, incluso entre espacios sintéticos:
un escritor obsoleto falla conservadoramente, aunque haya cambiado otro espacio.
LocalMutation fija expectedRevision al crear intención; SQLite exige igualdad con
la revisión de disco y de la instancia. expectedVersion es la versión de planta:
0 para creación, versión cargada para edición/borrado/riego. Todo cambio incrementa
esa versión; el nuevo evento comienza en 1 y no se reescribe. outbox almacena la
versión de su entidad (evento o planta); result_json también conserva la de planta.
Nunca se rebajan o actualizan expectativas para forzar un reintento.

Un conflicto conserva pendingMutation en el controlador para reconciliación
explícita; no hay resolución automática ni UI de conflictos en esta fase. Recargar
no transforma la intención retenida en una nueva con otra base. No se pretende
resolver conflictos remotos ni conservar borradores no confirmados tras cierre.

El repositorio SQLite exige spaceId en construcción y en la intención. Consultas,
actualizaciones y claves incluyen espacio. Solo el anónimo actual se construye en
la app; datos sintéticos temporales prueban aislamiento. SQL garantiza FK compuestas
de plantas/eventos a referencias y de dependencias a operaciones. En el outbox,
plant_ref_id tiene FK compuesta; entity_type/entity_id es polimórfica y su existencia,
tipo y correspondencia con la mutación/evento se garantizan en el DAO transaccional.
No hay FK SQL polimórfica. La incorporación de preferencias solo admite anonymous.

Revisión, versión, secuencia y posiciones se verifican antes de exceder INTEGER
64-bit. El agotamiento falla sin escritura parcial. Secuencia local ordena la
causalidad, no la hora; no hay prioridad por reloj ni dependencias entre espacios.

## Proyección temporal

La incorporación preserva exactamente la fecha visible E.2 y el baseline textual.
Una fecha UTC se clasifica comparable si ningún evento es posterior. Baseline más
reciente que los eventos es válido y no fabrica un riego. Null sin eventos también
es comparable. Nuevos eventos comparables usan max(fecha proyectada,evento),
equivalente al máximo de baseline/eventos por el invariante conservado.

- UTC coherente: conserva vista y baseline. Riego del día 9 con proyección del 10
  conserva evento del 9 y muestra el 10; diagnóstico new_event_before_projection.
- local_unzoned: texto y baseline intactos, legacy_hold y unresolved_local_time.
  No se interpreta como UTC ni se compara con eventos UTC.
- Evento posterior al valor visible, o visible null con eventos: legacy_hold y
  legacy_projection_mismatch; se conservan ambos valores sin cambiar la vista.
- En legacy_hold un riego NUEVO mantiene E.2: muestra el nuevo instante declarado,
  incluso anterior; conserva baseline, eventos y diagnóstico pendiente. No resuelve
  la incompatibilidad antigua ni convierte el baseline sin zona.
- Editar perfil no cambia baseline/fecha ni crea eventos. Borrar conserva historia
  y excluye planta del calendario; esta fase no admite regar una planta inactiva.

Los diagnósticos son persistentes, consultables en SQLite; no hay una nueva pantalla
para resolverlos. Los períodos continúan en 86400 segundos, sin sensores ni bombas.

## SharedPreferences y validación

LocalTreeRepository adapta intenciones a su snapshot original y conserva escritura
serializada, mensajes y comportamiento temporal. Retiene en memoria el candidato
para repetir un guardado fallido, incluido fallo después de persistir. No incorpora
cola durable ni las garantías SQLite de revisión/espacios/confirmación transaccional.
PlantSnapshot sigue siendo lectura y compatibilidad, no transporte.

Pruebas nuevas usan bases temporales FFI: actualización v1, rollback de apertura,
incorporación/reapertura, trigger de inmutabilidad, pérdidas de respuesta tras
COMMIT, replay antiguo tras edición posterior, colisiones de ID, revisiones,
dependencias, espacios sintéticos, límites y reglas temporales. Se conserva cobertura
anterior; la prueba que descartaba una intención pendiente cambia deliberadamente
para exigir reconciliación antes de aceptar otra acción.

Las compilaciones y los fallos inyectados FFI de la implementación no prueban
corte eléctrico, corrupción física, disco lleno Android, restauración coherente,
cifrado ni plataformas adicionales. Reglas de backup Android y dependencias intactas.
Resultados automatizados finales: 319 pruebas aprobadas y flutter analyze --no-pub
sin incidencias. flutter build web --no-pub correcto (57.2 s, dry run Wasm
correcto; no es validación de ejecución web/Wasm). APK debug compilado con
ORG_GRADLE_PROJECT_android.builder.sdkDownload=false (assembleDebug 56.5 s).
Avisos de soporte futuro: Gradle 8.14, AGP 8.11.1 y Kotlin 2.2.20; sin actualización.
Productos locales ignorados por Git. En la implementación no se operó el teléfono;
la instalación y validación física posteriores se documentan por separado.
Las primeras ejecuciones detectaron ajustes de compatibilidad y mensajes de error,
corregidos antes de esta suite final. Las pruebas E.3 añaden 20 casos netos a las
299 anteriores; la expectativa de descartar un intento incierto se cambió de forma
explícita para exigir reconciliación. No se ejecutaron pruebas PostgreSQL.

## Validación física Android completada

Se observó migración v1 → v2 en RMX5111, Android 16/API 36, conservando identidad,
comprobante, datos, fechas, historial y respaldos. Se preservaron 3 plantas activas,
1 eliminada, 4 referencias y 5 eventos; aparecieron 13 capturas y cero comandos
históricos. Crear/editar/regar/eliminar una planta de prueba confirmó cuatro comandos
local_only, secuencias 1–4 y tres dependencias. Tras detener y reabrir quedaron 3
activas, 2 eliminadas, 5 referencias, 6 eventos, 13 capturas y los mismos cuatro
comandos, sin duplicados. Integridad ok y cero errores FK en todas las copias.
Configuración de recordatorios conservada; entrega física no comprobada.
No se probaron corrupción, falta de espacio, cortes eléctricos ni restauraciones.
Las 319 pruebas, análisis y compilaciones previos no se repitieron durante la prueba
física ni en la preparación documental. Cierre Git E.3 autorizado por el usuario.

## Procedimiento de referencia para futuras validaciones

El recorrido E.3 anterior ya se ejecutó; esta lista se conserva como referencia,
no como autorización para repetir acciones sobre el teléfono.

1. Obtener autorización, seleccionar dispositivo y verificar paquete/firma de
   instalado y APK nuevo. Coordinarse si el teléfono está en otra app o en uso.
2. Conservar un respaldo consistente fuera de Git y comparar IDs/campos/eventos,
   identidad, marcadores y respaldos E.2 sobre una copia. Para datos no desechables,
   aprobar y verificar además respaldo externo/recuperación antes de actualizar.
3. Actualizar conservando datos, sin desinstalar ni limpiar. Abrir BlueFlora y
   comprobar v2, capturas equivalentes, fecha visible idéntica y outbox inicialmente
   vacío para el estado E.2. Origen y comprobante deben permanecer intactos.
4. Crear, editar, registrar un único riego y eliminar una planta de prueba desde
   la interfaz; comprobar sus comandos local_only, dependencias, UUID e historial.
5. Detener/reabrir únicamente BlueFlora y comparar persistencia de operaciones,
   datos, diagnósticos y secuencias. No presentar esto como reinicio de Android ni
   corte eléctrico. Corrupción, disco lleno o restauraciones destructivas quedan
   para un ensayo separado con autorización específica.
