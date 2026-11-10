> **Cierre autorizado de 3.2E.4 — 2026-11-10.** Hito Git v0.3.5;
> creación de commit y publicación en origin/main autorizadas, publicación pendiente
> de comprobación. Se conservan las limitaciones documentadas. E.5 no iniciada ni
> autorizada. Los estados de preparación anteriores quedan como trazabilidad.

# Estado vigente — cierre autorizado E.4 (2026-11-10)

Implementación y validación técnica de **3.2E.4 completadas; cierre autorizado, publicación Git pendiente**.
Hito Git autorizado **v0.3.5**, sin cambiar versiones internas ni crear tag/release.
Las **292 pruebas aisladas** aprobadas corresponden a la ejecución anterior;
no se repitieron para esta preparación documental.

Respaldo y restauración acreditados para el origen vacío; fallo inicial de
comparación CHECK diagnosticado y resuelto por aceptación exclusiva de las dos
expresiones completas de **bf-growth-diameter-exact-v1**. Se conservan intentos
fallidos y resoluciones en sus informes históricos. Migración conjunta de
desarrollo hasta **0005_mutation_gateway** completada; verificaciones posteriores
READ ONLY y carga/lifespan/liveness correctas, proceso temporal cerrado.
No hubo CRUD HTTP en desarrollo ni despliegue persistente.

Datos poblados sintéticos en pruebas no equivalen a un backfill poblado observado
en desarrollo. Rendimiento y PITR no acreditados. El contexto de propietario
confía en el proceso/conexión API; RLS no autentica credenciales runtime comprometidas.
Flutter continúa sin HTTP, login ni sincronización. **E.5 no iniciada ni autorizada**.
El usuario autorizó el cierre E.4 y el commit/push de los 56 archivos revisados.
La publicación se confirmará contra origin/main; este documento no la presume.

E.3 publicada en af2bd84dadae3fba8a8fd8119c54a2307520cfa9.
Ver [validación E.4](../backend/docs/sync/e4-validation-results.md),
[migración real](../backend/docs/sync/e4-development-migration-results.md) y
[contrato REST](../backend/docs/resources-api.md).

## Antecedente conservado E.3

# BlueFlora — transición técnica E.3

Estado al 2026-11-07, America/Mexico_City: **implementación local A/B/C y validación
Android de 3.2E.3 completadas; cierre E.3 autorizado por el usuario**.
Hito Git v0.3.4, sin tags ni releases y sin cambiar versiones internas.
La autorización de commit y push se limita a los 14 archivos revisados de E.3.
E.4 no se inició y no está autorizada. Flutter sigue sin HTTP, login,
cuentas, tokens ni sincronización.

El commit anterior es f168da0e1f7e20612fed42a9dd10f97c43db7ce2, BlueFlora v0.3.3
(cierre E.2). El cierre E.3 se identifica por el mensaje exacto:
BlueFlora v0.3.4 - Cola local persistente y proyeccion SQLite.
Consultar git log -1 --format='%H %s' y verificar publicación contra origin/main.

- [Esquema físico v2 y garantías E.3](../blueflora/docs/local-outbox.md).
- [Validación física E.3](../blueflora/docs/android-outbox-validation-results.md).
- Las secciones 1–8 conservan el antecedente E.2; el estado actual está en §9.

Este archivo es el punto de entrada para nuevas conversaciones ChatGPT/Codex.
Las reglas permanentes del repositorio están en [`../AGENTS.md`](../AGENTS.md).

## 1. Estado y arquitectura real al cierre E.2

Repositorio único: `blueflora/` contiene Flutter; `backend/` contiene la API Python
independiente. La versión v0.3.3 identifica el cierre en Git; no se modificaron
las versiones internas de paquetes (`pubspec.yaml` sigue en 1.0.0+1 y el backend
en 0.1.0). No se creó un tag ni una publicación de producción por este cierre.

Flutter mantiene funcionamiento local sin internet. Capas:

- `lib/domain/`: `Tree`, `WateringEvent`, `PlantSnapshot`, resúmenes y preferencias.
- `lib/application/`: `TreesController` compartido, configuración y recordatorios.
- `lib/data/tree_repository.dart`: contrato local utilizado por el controlador.
- `lib/data/local_tree_repository.dart`: implementación SharedPreferences anterior,
  conservada para destinos todavía no migrados y pruebas existentes.
- `lib/data/storage/`: SQLite, lectura conservadora del origen, respaldos,
  comprobante de identidad, fábrica condicional y política por plataforma.
- `lib/presentation/`: pantallas y sistema de diseño compartido Material 3,
  temas claro/oscuro/sistema. La UI recibe estados confirmados del controlador.
- `lib/services/notification_service.dart`: integración de notificaciones Android;
  cálculo de recordatorios separado y preferencias persistentes locales.

Solo Android activa la migración SQLite automáticamente. La fábrica está preparada
para sqflite en Android/iOS/macOS y FFI en Linux/Windows; los otros sistemas nativos
siguen usando SharedPreferences hasta validación específica. Web también conserva
SharedPreferences, mediante imports condicionales sin IO/FFI. La compilación web
pasó; eso no implica durabilidad equivalente a SQLite ni validación de otros SO.

El backend FastAPI/PostgreSQL existe y tiene autenticación y recursos REST,
pero **Flutter aún no utiliza HTTP, cuentas ni sincronización**. Los módulos de
dispositivos/telemetría/riego hidráulico/sync son bases modulares o diseño, no
integraciones de hardware implementadas. No hay Firebase ni Supabase como backend.

## 2. Entregas completadas

| Entrega | Resultado validado |
| --- | --- |
| 1.1–1.6 | Modelo/pruebas, repositorio seguro, validaciones/edición, estado compartido, detalle/historial, preferencias y notificaciones |
| 2.1 y 2.2A–F | Sistema visual y pantallas rediseñadas; auditoría integral; base v0.2.0 de 263 pruebas |
| 3.1 | Arquitectura propia, PostgreSQL, UUID y diseño hidráulico por zonas/sitios |
| 3.2A | Estructura FastAPI y liveness |
| 3.2B | PostgreSQL local, SQLAlchemy, Alembic, esquema inicial |
| 3.2C | Autenticación propia, Argon2id, sesiones y roles separados; 93 pruebas al cierre |
| 3.2D | Jardines, plantas, catálogo e historiales REST; 158 pruebas backend al cierre |
| 3.2E.1 | Contratos/invariantes/esquema objetivo de sincronización; documentación, no motor sync |
| 3.2E.2 | SQLite anónimo, migración local y recuperación; 299 pruebas Flutter, APK y validación física |
| 3.2E.3 | A/B/C local, SQLite v2 y validación Android completados; 319 pruebas; cierre autorizado |

El commit anterior al cierre E.2 es `321f9d2` (v0.3.2, diseño offline-first).
El cierre E.2 corresponde a `f168da0`, con mensaje
`BlueFlora v0.3.3 - SQLite y migracion local offline`; el cierre E.3 está en §9.

## 3. Persistencia E.2 y reglas que deben conservarse

SQLite v1 contiene siete tablas: `local_spaces` (solo anónimo), `storage_state`,
`recovery_backups`, `migration_runs`, `plant_references`, `plants`, `watering_events`.
Usa claves foráneas, journal DELETE, synchronous FULL y busy timeout 5000 ms.
La revisión local impide que un escritor obsoleto sobrescriba una vista nueva.
Planta y evento se confirman en una sola transacción; los eventos confirmados no
se descartan ni reescriben. El borrado visible conserva fila/referencia histórica.

La migración lee directamente el valor lógico de `trees` (clave Android
`flutter.trees`), distinguiendo ausencia y vacío. Conserva el envelope original
y SHA-256 tanto en archivo privado como en la tabla de respaldos. Persiste mapas
de IDs faltantes; relee/verifica datos e integridad antes de activar SQLite en el
mismo COMMIT. Las preferencias originales no se reescriben por la migración.

Si falla antes de activar y el origen/IDs están verificados e intactos, puede
mostrarse el origen en solo lectura con reintento. Si no puede verificarse, se
conserva el error y todos los datos; no se presenta un jardín vacío falso.
Después de activar, no se vuelve automáticamente al JSON antiguo. La fábrica
comprueba identidad de la base con un archivo `activation-guard`.

Plantas: UUID estable, nombre/especie libres, altura opcional, frecuencia entera
1–36500 días y último riego opcional. El calendario sigue períodos de 24 horas.
Fechas antiguas sin zona se conservan como `local_unzoned` con diagnóstico; no se
les inventa UTC/zona histórica. Eventos sin instante interpretable bloquean
migración; textos/IDs incompatibles no se truncan ni renombran silenciosamente.
Los IDs legados no UUID se conservan localmente con diagnóstico, sin declararlos
compatibles con la API futura. Un último riego inicial no crea eventos inventados.

Archivos Android, dentro del directorio privado de bases de la app:

- `blueflora_anonymous_v1.sqlite` y auxiliares coherentes del motor.
- `blueflora_anonymous_v1.sqlite.activation-guard`.
- `blueflora_migration_backups/<sha256>.json`.

No guardar ni subir esos archivos. Las preferencias de tema/horario y el registro
de identificadores de notificación siguen locales en SharedPreferences.

## 4. Dependencias y herramientas

Dependencias directas SQLite fijadas exactamente:

| Paquete | Versión |
| --- | --- |
| sqflite | 2.4.2 |
| sqflite_common_ffi | 2.3.7 |
| path_provider | 2.1.5 |
| path | 1.9.1 |
| crypto | 3.0.6 |

El lockfile es obligatorio. Entre las transitivas resueltas: sqlite3 2.9.4,
sqflite_android/darwin 2.4.5, sqflite_common 2.5.15, path_provider_android 2.3.1,
jni 1.1.2. El grafo resuelto exige Dart >=3.12 y Flutter >=3.44, aunque el mínimo
declarado en pubspec sea anterior; no prometer compatibilidad con Dart 3.9.2.
Otras versiones resueltas: SharedPreferences 2.5.4, notificaciones 17.2.4,
timezone 0.9.4. No hacer upgrade automáticamente.

Entorno verificado: Flutter 3.47.9, Dart 3.13.7; Gradle 8.14, AGP 8.11.1,
Kotlin 2.2.20, Java 17 usado por Flutter; Android minSdk 24, compile/targetSdk 36,
NDK 28.2.13676358. SDK del equipo: plataformas 34/35/36; CMake 3.22.1.
Platform 35 y CMake fueron instalados por el usuario con autorización específica
porque JNI los requiere. No extender esa autorización a más instalaciones.
Existen avisos de soporte futuro de Gradle/AGP/Kotlin, sin fallo actual de build.

Backend: Python 3.14.4 en `.venv`; versiones instaladas observadas al cierre:
FastAPI 0.162.0, Uvicorn 0.54.0, pydantic-settings 2.16.2, SQLAlchemy 2.1.8,
Alembic 1.20.1, Psycopg/binario 3.3.8, argon2-cffi 25.1.0,
email-validator 2.3.0, pytest 9.2.0, httpx 0.28.1.
Estos valores describen el entorno local; los rangos autorizados están en
`backend/pyproject.toml`, no hay una promesa de lockfile Python reproducible.

## 5. Backend, contratos y seguridad

Migraciones existentes: `0001_initial`, `0002_auth`, `0003_resource_permissions`.
Tablas de recursos: users, gardens, species, plants, growth_history y watering_events;
autenticación añade sesiones, refresh tokens y limitación de intentos.
UUID y TIMESTAMPTZ, especies/jardines opcionales, altura/diámetro de crecimiento
opcionales y conservación de historiales tras eliminar lógicamente plantas.

Roles de desarrollo/pruebas y ejecución separados. La API usa `blueflora_api`
en `blueflora_dev`; pruebas usan `blueflora_api_test` en `blueflora_test`.
Los roles de migración no se usan para HTTP. PostgreSQL solo escucha localmente.
FORCE RLS, USING/WITH CHECK y relaciones por propietario se comprobaron en 3.2D.
No hubo consultas, migraciones ni modificaciones PostgreSQL en esta fase local.

Autenticación: Argon2id; access/refresh opacos aleatorios, hashes SHA-256 en servidor,
access de hasta 15 minutos y sesión absoluta de 30 días; rotación/revocación y
rate limiting. Refresh perdido no se reintenta a ciegas: puede requerir nuevo login.
Funciones SECURITY DEFINER con propietario distinto de API, search_path seguro,
objetos cualificados y EXECUTE revocado de PUBLIC. Acceso inicial por correo exacto;
owner nunca se acepta como identidad del cliente. No hay correo real/verificación
de titularidad ni recuperación de contraseña implementados todavía.

Rutas actuales: `/health/live`, `/api/v1/auth/{register,login,refresh,logout}`,
`/api/v1/me`, jardines/plantas, especies (lectura), growth-history y watering-events.
Los contratos exactos están en `backend/docs/resources-api.md` y authentication.md.
Los endpoints `/sync/*`, CAS, ledger, feeds y bootstrap son diseño, no implementados.

SQLite ordinario no cifra. Se aprobó sandbox privado para esta fase anónima, sin
credenciales/tokens/cuentas en la base. No se cambiaron reglas Android de backup.
El archivo SHA-256 detecta cambios; no cifra datos ni protege frente a pérdida del
dispositivo. Credenciales backend solo en entorno/`.env` local ignorado, jamás
en este resumen, Git o registros. No buscar su contenido para continuar.

## 6. Validación y comandos

Resultado validado antes del cierre: análisis limpio, **299 pruebas Flutter
(263 anteriores + 36 nuevas)**, APK debug compilado y firma verificada. Build web
también pasó durante E.2. Backend: **158 pruebas** al cierre de 3.2D; no se repitieron
en E.2 porque no cambió el backend. No presentar esas 158 como ejecución nueva.

Desde `blueflora/`:

```bash
flutter analyze --no-pub
bash tool/test_local_storage.sh --reporter expanded
env 'ORG_GRADLE_PROJECT_android.builder.sdkDownload=false' flutter build apk --debug --no-pub
```

Si Flutter no está en PATH, puede utilizarse `/home/niereme/flutter/bin/flutter`
y `BLUEFLORA_FLUTTER_BIN=/home/niereme/flutter/bin/flutter` para el script.
FFI en este Ubuntu necesita el nombre `libsqlite3.so`; el script detecta
`libsqlite3.so.0` instalada y genera un enlace solo en `.dart_tool`, comprobando
el existente y exportando LD_LIBRARY_PATH solo para ese proceso. No instala nada.
Ejecutar `flutter test` sin la preparación en este equipo falla al cargar SQLite.

El APK queda en `blueflora/build/app/outputs/flutter-apk/app-debug.apk`: artefacto
local excluido de Git. Los informes no sustituyen una nueva ejecución si hay
cambios futuros. Arranque backend según `backend/README.md`; no ejecutar pruebas
PostgreSQL o migraciones como parte de una tarea exclusivamente Flutter.

Se verificó físicamente en un RMX5111, Android API 36: actualización `-r` compatible,
3 plantas/4 eventos originales conservados, creación, edición, un riego manual,
borrado con confirmación e historial retenido. Tras detener/reabrir, quedaron
3 plantas visibles y 5 eventos; los originales seguían idénticos. No se reinició
todo Android, no se provocó corrupción/falta de espacio y no hubo instalación limpia.
Los datos actuales del teléfono son pruebas desechables; no hay usuarios reales.
Desinstalar o limpiar datos sigue requiriendo permiso específico.

## 7. Documentación y límites pendientes

- `blueflora/docs/local-storage.md`: esquema, migración, protección y entorno.
- `blueflora/docs/android-storage-validation-results.md`: evidencia física resumida,
  sin copias de bases, screenshots, XML privados o datos originales del teléfono.
- `blueflora/docs/android-storage-validation.md`: procedimiento de respaldo externo
  propuesto para futuros datos no desechables; no imponerlo a los actuales ensayos.
- `backend/docs/sync/`: especificación E.1, contratos v1, esquema objetivo, seguridad,
  plan de subfases y matriz de pruebas. El esquema objetivo completo no está creado.
- `backend/docs/{architecture,database,authentication,resources-api}.md` y README.

Pendientes: cifrado/backup y restauración coherente antes de cuentas reales;
resolución explícita de fechas/IDs incompatibles para sincronización; otros destinos
nativos; fallos físicos destructivos y todos los tamaños de pantalla. No hay aún
restaurador UI/exportador ni garantía frente a pérdida del teléfono. Si una
restauración omite simultáneamente DB y comprobante, no puede demostrarse usando
solo preferencias si existió una base más reciente: no prometer recuperación total.
Los marcadores/respaldos no son una cola durable de operaciones.

## 8. Antecedente del siguiente paso al cerrar E.2

Según E.1, **3.2E.3: cola durable, proyección local y espacios**. Primero revisar
el código ya cerrado, los invariantes y el esquema objetivo; proponer el alcance
pequeño y las migraciones SQLite locales necesarias. Las mutaciones y sus comandos
deben confirmarse juntas, preservar UUID/orden por entidad y resistir interrupciones.
El diseño de espacios no autoriza activar cuentas ni tokens en esta entrega.
HTTP, cambios PostgreSQL/revisiones REST, sesiones móviles y push/pull corresponden
a subfases posteriores y requieren autorización propia. Mantener operaciones locales
y recordatorios actuales, sin pérdidas ni retornos a snapshots antiguos.

Para reanudar una conversación, aportar este archivo y especificar la subfase y
alcance autorizados. Revisar AGENTS.md y Git antes de editar; no inferir permiso
de implementación de este resumen ni del cierre del commit anterior.

## 9. Estado actual E.3 y cierre autorizado

Implementación y validación completadas. La fábrica Android abre user_version=2
en la misma ruta blueflora_anonymous_v1.sqlite, manteniendo database_id y guardia.
Las siete tablas E.2 permanecen; se añaden prior_state_records, outbox,
outbox_dependencies y local_diagnostics. Las capturas previas conservan las filas
originales fuera de la cola. Solo nuevas intenciones explícitas generan comandos
local_only; modificación, evento, comando, dependencias y contadores comparten COMMIT.
Se rechaza save(snapshot) en SQLite; su ruta privada se reserva a incorporación
antes de activar. No hay fallback a preferencias antiguas tras la activación.

Revisión global y versión de planta se comprueban en la transacción. Un reintento
confirmado se reconoce antes de rechazar su revisión antigua y devuelve la proyección
vigente. Se conserva la identidad/payload del intento. Baselines ambiguos o con
discrepancias mantienen comportamiento E.2 con diagnóstico, sin convertir zonas;
las plantas comparables no retroceden con un evento anterior. Se conservan UUID,
historial tras borrado, respaldos y períodos de 86400 segundos.

Solo Android activa SQLite y únicamente se habilita el anónimo actual; espacios
adicionales son sintéticos en pruebas temporales. SharedPreferences sigue en otros
destinos sin atribuirle garantías de outbox durable. Backend FastAPI/PostgreSQL,
autenticación, RLS, dependencias, herramientas y backup Android no cambiaron.
La documentación E.1 registra la adaptación de capturas fuera del outbox.

### Evidencia automatizada de la implementación

- flutter analyze --no-pub: sin incidencias.
- bash tool/test_local_storage.sh --reporter expanded: 319 pruebas aprobadas
  (299 anteriores y 20 adicionales; adaptación explícita de un reintento pendiente).
- flutter build web --no-pub: correcto.
- APK debug compilado con ORG_GRADLE_PROJECT_android.builder.sdkDownload=false.
- Avisos de soporte futuro Gradle/AGP/Kotlin; ninguna actualización realizada.

Estas ejecuciones pertenecen a la implementación. No se repitieron suites ni
compilaciones durante la validación física ni en esta preparación documental.
Las 158 pruebas backend siguen siendo el antecedente de 3.2D, no ejecución nueva.

### Evidencia física Android posterior

RMX5111, Android 16/API 36, paquete com.example.blueflora. Firma compatible y
actualización -r conservando datos; APK instalado idéntico al verificado. Se observó
migración real v1 → v2: 3 plantas activas, 1 eliminada, 4 referencias y 5 eventos
preservados; 13 capturas y cero comandos históricos. Crear, editar, registrar un
riego manual y eliminar una planta de prueba confirmó cuatro comandos local_only,
secuencias 1–4 y tres dependencias. Revisión global 4 → 8.

Tras detener/reabrir: 3 activas, 2 eliminadas, 5 referencias, 6 eventos, 13 capturas
y cuatro comandos idénticos, sin duplicados. Historial conservado con nombre y
etiqueta Planta eliminada. Identidad, guardia, fechas, originales, preferencias
y respaldos preservados. Integridad ok y cero errores FK en las copias coherentes.
Configuración de recordatorios conservada; entrega física de notificación no
comprobada. No se probaron corrupción, falta de espacio, cortes eléctricos,
restauraciones ni reinicio completo de Android. No ampliar las garantías FFI a
esos escenarios. Ver el informe físico enlazado para procedimiento y límites.

### Cierre Git autorizado y siguiente límite

El usuario autorizó el commit de los 14 archivos revisados y push normal a
origin/main con el mensaje exacto:
BlueFlora v0.3.4 - Cola local persistente y proyeccion SQLite.
El resultado de publicación debe verificarse contra main remoto; no usar force,
merge ni rebase automático si el remoto avanzó o rechaza el push.
.vscode/ permanece fuera; no incluir secretos, bases, respaldos privados, capturas
ni builds. No se modificaron pubspec ni versiones internas; no hay tags ni releases.
No se repitieron pruebas ni compilaciones por los ajustes documentales de cierre.
E.4 no se inició y requiere autorización independiente. Cuentas móviles, HTTP,
PostgreSQL/CAS y motor sync siguen fuera de esta entrega y sin iniciar.
