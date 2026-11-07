# Validación física de la Fase 3.2E.2

Estado: validación física del alcance solicitado completada y Fase 3.2E.2
cerrada con autorización del usuario el 2026-11-07.

## Alcance autorizado

El usuario confirmó que todas las plantas e historiales del teléfono son datos
de prueba desechables. Se autorizó actualizar conservando datos y probar migración
y operaciones. No se autorizó desinstalar ni limpiar datos sin una consulta previa.
Para estos datos se utilizó una comparación temporal sencilla; el procedimiento
de respaldo externo para futuros usuarios permanece documentado, no es un requisito
adicional impuesto a esta prueba de desarrollo.

## Entorno y actualización

- Teléfono RMX5111, Android API 36, arm64-v8a.
- Paquete existente y nuevo: `com.example.blueflora`, versión 1.0.0, código 1.
- La instalación existente es depurable y permitió `run-as` sin root.
- Certificado SHA-256 idéntico entre el APK instalado y el generado.
- `adb install -r` terminó en `Success`. No se desinstaló ni se limpiaron datos.

## Migración real comprobada

Se abrió la versión nueva, luego se detuvo únicamente BlueFlora para obtener una
copia consistente de su base y contrastarla en Ubuntu. No se escribieron tablas
directamente mediante ADB: la migración la ejecutó la aplicación.

- SQLite activo (`storage_state.active=1`), migración confirmada, revisión inicial 0.
- Se conservaron 3 plantas y 4 eventos con los mismos UUID/identificadores.
- Nombre, especie, altura, frecuencia, fechas y contenido de eventos equivalentes
  al envelope original. No se fabricaron eventos a partir del último riego.
- La clave original `flutter.trees` permaneció idéntica antes y después.
- Las tres fechas de plantas sin zona permanecieron `local_unzoned`, con diagnóstico
  explícito y sin imponer UTC. No se afirma haber resuelto su zona histórica.
- `PRAGMA integrity_check`: `ok`; `foreign_key_check`: sin errores.
- Respaldo JSON privado del teléfono idéntico al envelope de `recovery_backups`;
  SHA-256 correcto. El respaldo interno no es protección ante pérdida del teléfono.

## Operaciones realizadas desde la interfaz

- Creación: formulario real, planta `SQLiteE2-Prueba`, especie `EspecieE2`, altura
  introducida como `1,5` y frecuencia 3 días. Se guardó altura 1.5, UUID nuevo,
  cuatro plantas visibles y revisión 1. Ningún evento adicional inventado.
- Tras detener y reabrir la app se comprobó la persistencia de la nueva planta.
  Las tres plantas migradas y los cuatro eventos originales seguían sin cambios.
- Edición: nombre `SQLiteE2-Editada`, especie `EspecieE2Editada`, altura introducida
  como `2,25` (persistida 2.25) y frecuencia 5 días. Se conservaron UUID y fecha
  del último riego; cuatro eventos, revisión 2. Se cerró/reabrió la aplicación.
- Riego: desde la ficha individual se registró una sola vez. Se confirmó un único
  evento `manual_registration`, enlazado por el mismo UUID, junto con el nuevo
  último riego; cinco eventos totales, revisión 3. La fecha local y la UTC del
  evento representan el mismo instante en la zona del dispositivo. Persistió tras
  cerrar/reabrir y apareció como primer registro del historial global.
- Eliminación: se utilizó la confirmación de eliminación solamente sobre la planta
  creada en esta prueba. Quedaron tres plantas visibles, cinco eventos y revisión 4.
  La fila de prueba quedó marcada `deleted=1`; su referencia y su único evento se
  conservaron. Tras cerrar/reabrir, Inicio mostró total 3 e Historial mostró ese
  evento con la etiqueta `Planta eliminada`.
- Comparación final: las tres plantas y los cuatro eventos iniciales permanecen
  idénticos; todos los IDs de eventos son únicos. `trees` continúa intacta. La base
  mantiene integridad `ok`, sin errores de FK y con el único respaldo original.

Durante la continuación el teléfono cambió a otra pantalla. Se pausaron las
interacciones para no tocar otras aplicaciones y se solicitó coordinación al
usuario antes de seguir. Tras su confirmación se retomaron exclusivamente las
operaciones en BlueFlora. No se envió ningún mensaje ni se actuó sobre otra app.

## Límites

La suite automatizada previamente aprobada consta de 299 pruebas y el APK debug
compila. La evidencia anterior es una comprobación física adicional, no una nueva
ejecución de la suite. No se provocaron errores de disco ni corrupción en el teléfono;
la recuperación ante esos fallos sigue cubierta por pruebas automatizadas y su
validación física deliberada no se declara realizada.

Se verificaron también el comprobante de identidad de la base y el respaldo final.
El log reciente del proceso actual no mostró errores fatales ni excepciones Flutter.
No hubo instalación limpia, restauración destructiva, borrado general ni reinicio
completo del sistema operativo: "reiniciar" en esta prueba significa detener el
proceso de BlueFlora y volver a abrirlo. No se afirma haber probado un corte de
energía, corrupción física o agotamiento de disco en el teléfono.

En el teléfono quedan las tres plantas originales y los cuatro eventos originales,
más un evento de prueba asociado a la planta eliminada. No se ha borrado ese evento.

No se modificaron PostgreSQL, sincronización, dependencias ni reglas de respaldo
Android. No se realizaron commits ni subidas. En esta validación no se alteró el
código de ejecución: solo se documentaron resultados y se operó la app instalada.
