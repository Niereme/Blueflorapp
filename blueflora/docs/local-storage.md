# Estado actual: SQLite v2 local — E.3 implementada y validada

La implementación E.3 añade intenciones, outbox local_only, capturas previas y
proyección conservadora. Ver [esquema y garantías E.3](local-outbox.md).
La ruta de base y las protecciones E.2 permanecen. Implementación A/B/C y validación
Android completadas; cierre E.3 autorizado por el usuario como hito Git v0.3.4.
Ver [resultados físicos E.3](android-outbox-validation-results.md). Las 319 pruebas,
análisis limpio y builds web/APK corresponden a la implementación; no se repitieron
durante la prueba física ni en esta preparación documental. El resto del documento
conserva el antecedente E.2. E.4 no está iniciada ni autorizada.

# Almacenamiento anónimo SQLite — Fase 3.2E.2 cerrada

No contiene red, cuentas, tokens, cambios PostgreSQL ni control de hardware.
La compilación y el recorrido de migración/operaciones se verificaron en Android
real. El usuario autorizó el cierre el 2026-11-07; las limitaciones documentadas
permanecen explícitas. Ver el [resumen de transición](../../docs/TRANSICION_TECNICA.md).

## Estado de plataformas

La fábrica usa importaciones condicionales: web no importa IO/FFI. La política
prepara SQLite para Android, mientras iOS, macOS, Linux y Windows mantienen
SharedPreferences hasta validarse en cada destino. El adaptador nativo elige
sqflite en Android/iOS/macOS y FFI en Linux/Windows. Compilar web no demuestra
durabilidad del almacenamiento del navegador ni validación de otros sistemas.

## Esquema local, versión 1

- `local_spaces`: exclusivamente el espacio anónimo; no hay cuentas.
- `storage_state`: activación, inicialización, revisión e identidad de esta base.
- `recovery_backups`: envelope íntegro del valor lógico de `trees` y SHA-256.
- `migration_runs`: estado, mapa de IDs ausentes y diagnósticos recuperables.
- `plant_references`: identidades históricas, incluso de plantas eliminadas.
- `plants`: datos de plantas, orden y borrado visible sin eliminar su referencia.
- `watering_events`: eventos manuales y nombre histórico, sin simular riegos físicos.

Plantas y eventos se escriben en una transacción. El repositorio confirma memoria
después del COMMIT y rechaza escritores con una revisión local obsoleta. No se
permite descartar ni sobrescribir eventos ya confirmados. Cada conexión usa FK,
busy timeout, journal DELETE y synchronous FULL. Estas medidas no garantizan
supervivencia frente a hardware defectuoso o un filesystem que no respete fsync.

## Migración y recuperación

1. Leer directamente `TreePreferencesStore.read`, sin el loader antiguo que puede
   actualizar automáticamente las preferencias. Distinguir ausencia y vacío.
2. Guardar un envelope con `keyPresent` y strings originales ordenados en un archivo
   privado verificado mediante lectura y SHA-256, antes de importar. También se
   guarda en `recovery_backups`. No es copia byte a byte del XML de Android.
3. Confirmar mapa de IDs faltantes antes de poblar tablas. Los UUID existentes y
   referencias de eventos se conservan; no crear plantas para eventos huérfanos.
4. Poblar, releer y comparar la instantánea; verificar integridad/FK y confirmar
   activación dentro de la misma transacción. Nunca fabricar eventos desde la
   fecha de último riego. El flujo existente decide la primera apertura sin datos.
5. Conservar preferencias y respaldos originales. Si cambió la fuente antes de
   activar, no aplicar el candidato anterior: capturar y verificar otra versión.

Los nombres no se truncan. Los textos que requerirían recorte, JSON desconocido,
IDs duplicados, fechas inválidas y eventos sin zona bloquean la activación y
conservan el origen. Los IDs legados no UUID permanecen íntegros con diagnóstico;
no se declaran compatibles con una futura API.

Las fechas de plantas sin zona se preservan como fecha local (`local_unzoned`),
sin asignar UTC ni reconstruir una zona histórica. Mantienen la interpretación
local que ya usa Flutter. El respaldo conserva su representación original. El
diagnóstico advierte la ambigüedad: su resolución para sincronización futura está
pendiente. Las horas locales inexistentes detectables en el dispositivo bloquean
la migración. No se afirma haber desambiguado cambios horarios históricos.

Un fallo posterior a verificar el origen y confirmar sus IDs permite mostrarlo
en **solo lectura**, únicamente si la base confirma que no está activa y el origen
sigue siendo idéntico. El aviso permite reintentar. No se permiten modificaciones
que destruyan el respaldo original. Si no puede verificarse lo anterior, se muestra
el error de carga y se conserva todo para recuperación, sin una lista vacía falsa.

Después de activar SQLite no se consulta ni usa como fallback el JSON anterior.
La fábrica nativa conserva un comprobante de identidad junto a la base y rechaza
una base ausente o distinta. Corrupción/error de lectura de una base activa requiere
recuperarla; nunca volver automáticamente a preferencias obsoletas. Los respaldos
y diagnósticos son archivos privados de recuperación, no un nuevo exportador UI.

## Seguridad y copias Android

SQLite ordinario no cifra datos. Se utilizan directorios privados; no hay secretos
en la base. No se modificaron el manifiesto ni las reglas de respaldo. El respaldo
interno NO protege ante desinstalación, pérdida o avería del dispositivo.

Queda pendiente aprobar y probar una política de restauración coherente que cubra
base, journal/comprobante y respaldos, conservando el mecanismo actual mientras
se decide. No se ha aprobado excluir datos de nube o transferencias. Restaurar
solo las preferencias antiguas sin la base/comprobante no permite demostrar que
existan datos SQLite más recientes en otro respaldo: esta limitación sigue abierta.

## Validación sin modificar el sistema Ubuntu

Las cinco dependencias directas están fijadas a las versiones aprobadas. No se
actualizan Flutter, Dart, Gradle, AGP, Kotlin ni el SDK Android por este diseño.

FFI busca `libsqlite3.so`. Este equipo dispone de `libsqlite3.so.0`, pero no del
enlace de desarrollo. El script versionable `tool/test_local_storage.sh` hace la
preparación reproducible desde una copia del repositorio: detecta la biblioteca
instalada, crea un enlace únicamente en `.dart_tool/blueflora-test-libs/` cuando
falta el nombre sin versión, comprueba cualquier enlace previo y configura
`LD_LIBRARY_PATH` solo para su proceso. No sobrescribe enlaces distintos, no
instala componentes y no modifica perfiles del shell ni rutas del sistema.
Desde `blueflora/`:

```bash
bash tool/test_local_storage.sh --reporter expanded
flutter analyze --no-pub
flutter build web --no-pub
```

Puede indicarse el ejecutable con `BLUEFLORA_FLUTTER_BIN=/ruta/a/flutter` si no
está en PATH. El script pasa los argumentos adicionales a `flutter test --no-pub`.
Puede repetirse y reconstruye el enlace si se regenera `.dart_tool`.

No es una instalación ni una solución de distribución Linux. Ejecutar tests sin
ese enlace/ruta en este equipo falla al cargar SQLite. El destino Linux aún no
activa la migración automáticamente. No se instalaron paquetes con sudo.

`path_provider_android 2.3.1` incorpora `jni 1.1.2`, que declara compileSdk 35.
El usuario instaló Platform 35 mediante el siguiente comando autorizado (rutas
verificadas); permanecen disponibles las plataformas 34 y 36:

```bash
sudo env JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 /usr/lib/android-sdk/cmdline-tools/13.0/bin/sdkmanager --sdk_root=/usr/lib/android-sdk --install "platforms;android-35"
```

Se verificaron `source.properties` (API 35, Android 15, revisión 2), el registro
`package.xml` y la integridad ZIP de `android.jar`, incluida `Activity.class`.
El intento inicial desde el agente no pudo autenticar sudo; el usuario completó
la instalación en su terminal y lo confirmó. No se solicitaron contraseñas por el
chat ni se ejecutaron otros comandos sudo. La compilación de validación desactiva
descargas automáticas de componentes SDK solo para ese proceso:

```bash
env 'ORG_GRADLE_PROJECT_android.builder.sdkDownload=false' flutter build apk --debug --no-pub
```

La propiedad de Gradle se pasa por entorno; no se modifican `gradle.properties`,
versiones, permisos del SDK ni reglas de respaldo Android.

### Resultado de la validación con Platform 35 y CMake 3.22.1

- `flutter analyze --no-pub`: sin problemas.
- Suite completa mediante `bash tool/test_local_storage.sh --reporter expanded`:
  299 pruebas aprobadas (263 anteriores y 36 nuevas).
- Script FFI comprobado desde un directorio temporal limpio y al repetirlo;
  no depende de un enlace manual previo ni modifica el sistema.
- CMake: instalado por el usuario y verificado en
  `/usr/lib/android-sdk/cmake/3.22.1`; `source.properties` declara revisión 3.22.1.
  El `CMakeCache.txt` generado por Gradle para JNI arm64-v8a confirma esa ruta y
  versión 3.22.1, junto con el NDK existente 28.2.13676358.
- APK debug: compilación exitosa con descargas SDK desactivadas, sin requerir
  componentes adicionales. Artefacto: `build/app/outputs/flutter-apk/app-debug.apk`.
  `apksigner verify --verbose` verifica la firma v2, con un firmante. Esto no
  demuestra que coincida con la firma de la versión instalada en un teléfono.
- SHA-256 del APK de esta validación:
  `7e44c22225d317e79e2c82d6751458b982e6e29313219fc3b2265bbe7fa9f03d`.
- En la validación posterior ADB reconoció un RMX5111 con Android API 36. Se
  actualizó conservando datos y se verificaron migración y operaciones sobre los
  registros de prueba desechables autorizados. Ver
  [resultados físicos](android-storage-validation-results.md).

La compilación emitió avisos de soporte futuro de Gradle/AGP/Kotlin; no se
actualizaron esas herramientas ni se cambiaron las dependencias. No hay bloqueos
de compilación pendientes en esta ejecución. El éxito de tests FFI y de compilación
no reemplaza por sí solo la validación de canales nativos Android. El recorrido
normal se comprobó después en el teléfono; los fallos destructivos no se provocaron.

Las pruebas de interrupción inyectan fallos entre etapas y reabren SQLite real;
no equivalen a cortar energía en Android. Se comprobó persistencia deteniendo y
reabriendo la app en el teléfono, sin provocar corrupción ni falta de espacio.
La recuperación ante fallos destructivos y la presentación con todos los tamaños
de pantalla no se declaran verificadas físicamente. No ejecutar downgrade al
repositorio antiguo tras confirmar nuevas escrituras SQLite.

## Propuesta previa a cualquier prueba sobre datos reales Android

El siguiente procedimiento de respaldo externo para datos no desechables sigue
siendo una propuesta. La validación simplificada del teléfono con registros de
prueba ya se ejecutó, según la autorización posterior del usuario; no requiere
imponerle este procedimiento completo.

El procedimiento operativo propuesto, con comandos de captura y comprobación,
está en [android-storage-validation.md](android-storage-validation.md). No ejecutar
la actualización antes de verificar un respaldo externo y ensayar su recuperación.

1. Registrar la versión instalada y conservar el APK correspondiente. Identificar
   el paquete y comprobar si permite `adb shell run-as com.example.blueflora`
   (solo builds depurables). Si no lo permite, detenerse: no usar root ni borrar
   datos; acordar antes otro mecanismo de exportación y recuperación.
2. Con autorización para la prueba, detener la app sin desinstalarla ni limpiar
   datos. Crear con `run-as` una copia consistente de sus datos privados hacia
   Ubuntu, incluyendo preferencias y, si existen, SQLite, archivos auxiliares,
   comprobante de identidad y respaldos. Guardarla fuera del repositorio, con
   permisos restrictivos; no imprimir ni subir su contenido. No copiar una DB
   abierta ignorando su journal.
3. Verificar el archivo, su SHA-256 y los recuentos/IDs de plantas y eventos sobre
   una copia. Conservar otra copia en un medio seguro separado del teléfono.
   Probar lectura y restauración en emulador/dispositivo de pruebas aislado antes
   de instalar/abrir el APK migrador en el teléfono principal.
4. Solo después de aprobar esa verificación, actualizar el APK conservando paquete,
   firma y datos; abrir y comparar IDs, valores e historial con el respaldo. Un
   error de firma no autoriza desinstalar: detenerse y resolverlo.
5. Si falla, detener la app y capturar también el estado fallido para diagnóstico.
   Cualquier restauración que reemplace archivos requiere autorización explícita.
   Recuperar base, comprobante y preferencias como un conjunto compatible, nunca
   mezclar una DB reciente con metadatos antiguos. Si ya hubo nuevas escrituras
   SQLite, no restaurar silenciosamente el respaldo previo ni volver al APK viejo:
   preservar y recuperar primero esos cambios.

No se modifican las reglas de respaldo Android como parte de esta propuesta.
