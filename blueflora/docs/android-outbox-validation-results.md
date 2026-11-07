# Validación física Android — BlueFlora 3.2E.3

Fecha de informe: 2026-11-07, America/Mexico_City.
Resultado: implementación A/B/C y validación física completadas satisfactoriamente.
Cierre Git de E.3 autorizado posteriormente por el usuario como hito v0.3.4;
sin tags ni cambios de versiones internas. E.4 sigue sin iniciar ni estar autorizada.

## Alcance y preparación

El usuario autorizó actualización conservando datos y operaciones sobre registros
de prueba desechables. Al encontrar el launcher visible se solicitó coordinación;
el usuario respondió que podía continuarse únicamente con BlueFlora.
No se operaron otras apps ni se cambió el reloj, desinstaló la app, limpiaron datos,
instalaron componentes de sistema o alteraron tablas para fabricar resultados.

- Dispositivo comprobado: RMX5111, arm64, Android 16 / API 36.
- Paquete: com.example.blueflora, versión 1.0.0, código 1; build depurable.
- Commit de referencia permanece f168da0e1f7e20612fed42a9dd10f97c43db7ce2,
  con cambios locales E.3 conservados.
- APK: build/app/outputs/flutter-apk/app-debug.apk de la compilación E.3 previa.
  Ningún archivo de entrada de lib/, Android, pubspec o lock era posterior al APK;
  no se modificó código durante esta validación. Se verificó posteriormente que
  los bytes del APK instalado eran idénticos a los del APK local verificado.
- SHA-256 del APK:
  9d492754f94a55d111653275975884ca35d7639140287bb5b2eb70a5aea86cfc.
- apksigner: firma v2 válida, un firmante. Certificado SHA-256 idéntico en APK
  anterior instalado y nuevo:
  d39efdb3d088baebd80c573a2e8f7929188cb24c020babe4f0cbd20b08ebe882.
- Actualización: adb install -r sobre el dispositivo seleccionado; resultado Success.
  No se desinstaló ni se borró información.

Antes de actualizar se detuvo solo BlueFlora y se confirmó ausencia de su proceso.
Se copió mediante run-as un tar coherente de databases/ y shared_prefs/ a un
directorio temporal privado fuera de Git. Incluye base, guardia, auxiliares presentes
y respaldos internos. Se repitió el procedimiento tras cada operación y reapertura.
Las inspecciones SQLite se hicieron en copias locales abiertas en modo de solo
lectura. Los artefactos privados no se adjuntan ni incorporan al repositorio.
La copia temporal en el equipo no constituye una política de respaldo permanente.

## Estado realmente encontrado y migración observada

La base instalada era físicamente v1; se observó su actualización real a v2 al
abrir el APK E.3. No se restauró una base antigua ni se simuló esta migración.

| Momento | Esquema | Activas | Filas eliminadas | Referencias | Eventos | Capturas | Outbox | Dependencias | Revisión |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Antes de actualizar | 1 | 3 | 1 | 4 | 5 | No existe | No existe | No existe | 4 |
| Después de migrar | 2 | 3 | 1 | 4 | 5 | 13 | 0 | 0 | 4 |
| Creación | 2 | 4 | 1 | 5 | 5 | 13 | 1 | 0 | 5 |
| Edición | 2 | 4 | 1 | 5 | 5 | 13 | 2 | 1 | 6 |
| Riego manual | 2 | 4 | 1 | 5 | 6 | 13 | 3 | 2 | 7 |
| Eliminación confirmada | 2 | 3 | 2 | 5 | 6 | 13 | 4 | 3 | 8 |
| Tras detener/reabrir | 2 | 3 | 2 | 5 | 6 | 13 | 4 | 3 | 8 |

Comparaciones efectuadas sobre filas completas:

- database_id idéntico y mismo activation-guard, compatible en todas las copias.
  La identidad exacta se conserva solo en la evidencia temporal privada.
- Todas las columnas E.2 de plantas, eventos, referencias y estado coinciden tras
  migrar; UUID, identificadores, textos, fechas y marcas de borrado conservados.
- recovery_backups, migration_runs, mapas/diagnósticos E.2 y preferencias intactos.
  Los archivos de respaldos internos permanecieron idénticos también al finalizar.
- 13 capturas: 4 plantas, 4 referencias y 5 eventos. row_json coincide con cada fila
  original y su SHA-256 es correcto; procedencia sqlite_v1. Se conservan las filas
  de plantas eliminadas y sus referencias/historiales.
- Cero comandos tras migrar: ninguna captura se presentó como creación o riego nuevo.
- Cuatro diagnósticos locales tras incorporar; cinco tras crear la planta de prueba.
  No se resolvieron silenciosamente las representaciones temporales locales.

## Operaciones observadas desde la interfaz

Se utilizó exclusivamente una planta nueva identificable; no se modificaron plantas
originales. Los controles de edición/riego/eliminación se localizaron dentro de su
propia tarjeta. Las escrituras las ejecutó BlueFlora desde la UI.

| Acción | Resultado físico y durable | Secuencia | Versión de planta | Dependencia |
|---|---|---:|---:|---|
| Crear | SQLiteE3-Prueba, especie de prueba, altura 1.5 m, frecuencia 3 días; un plant.create | 1 | 1 | Ninguna |
| Editar | SQLiteE3-Editada, especie modificada, altura 2.25 m, frecuencia 5 días; un plant.update | 2 | 2 | Creación |
| Registrar riego | Un único evento manual y watering_event.append; nombre histórico SQLiteE3-Editada | 3 | 3 | Edición |
| Eliminar | Confirmación aceptada; planta oculta con deleted=1, sin pérdida de evento; un plant.delete | 4 | 4 | Riego |

Los cuatro comandos son local_only, con UUID únicos y fingerprint correcto de
intent_json. La versión del evento es 1; el resultado local del comando conserva
además la versión de planta. Se comprobaron identidad de entidad, secuencias 1–4,
versiones y las tres dependencias causales.

La edición conservó UUID, baseline, representación temporal y último riego, sin
crear eventos. El registro manual conservó el baseline, creó un solo evento y su
fecha UTC representa el mismo instante que la proyección almacenada. No se cambió
el reloj ni se convirtió el baseline sin zona a UTC. La creación con baseline
inicial no fabricó un evento. No se accionó ni verificó hardware de riego.

La eliminación se realizó desde la tarjeta de prueba y mediante el diálogo de
confirmación existente, que es genérico y no repite el nombre. La copia posterior
comprobó que solo quedó eliminada la nueva identidad; todas las plantas originales
permanecieron idénticas.

## Persistencia, historial y recordatorios

Se detuvo y reabrió BlueFlora entre comprobaciones y después de las cuatro acciones.
Tras la reapertura final, todas las filas SQLite eran exactamente iguales a la copia
posterior a eliminar, incluidos payloads, IDs, fechas, secuencias, dependencias,
diagnósticos y capturas. No hubo duplicados: cuatro UUID de operación y seis de evento.
Las 13 capturas y sus hashes permanecieron inalterados. Los originales siguen
idénticos al estado migrado; el único evento añadido pertenece a la planta de prueba.

Observación UI: Inicio muestra 3 plantas. Historial muestra el evento de prueba con
su nombre histórico y la etiqueta Planta eliminada después de reabrir. La pantalla
de configuración y su control de recordatorios se observaron sin cambiar opciones.
La configuración persistida de BlueFlora y los identificadores previos del registro
de avisos se conservaron. El control visual coincide con la configuración anterior.
La clave original trees también permanece idéntica.
No se observó ni se afirma entrega física de una notificación programada.
Se dejó BlueFlora abierta en Inicio.

## Integridad, incidencias y límites

En todas las copias: PRAGMA integrity_check = ok; foreign_key_check sin errores.
El comprobante coincide con database_id. La consulta sobre una copia verifica
consistencia de datos; no se presenta el foreign_keys por defecto de Python como
prueba de la configuración de la conexión Android de la app.

No se detectó fallo funcional de la app en este recorrido. El log del último
proceso de BlueFlora no mostró FATAL EXCEPTION, E/flutter ni Unhandled Exception;
no es una afirmación sobre todos los procesos o todos los escenarios posibles.

Incidencias de instrumentación, sin código de aplicación modificado:

- Dos lecturas de uiautomator inmediatamente tras abrir no devolvieron XML;
  se repitieron antes de continuar las acciones correspondientes.
- La selección de texto mediante combinación de teclas no seleccionó los campos;
  se corrigieron y verificaron los cuatro valores antes de guardar la única edición.
- Una comprobación auxiliar esperaba el nombre dentro del diálogo genérico; esa
  expectativa no se cumplió. La selección de tarjeta y la comparación posterior
  de identidades comprobaron que la eliminación afectó únicamente a la prueba.

No se ejecutaron corrupción, falta de espacio, cortes eléctricos, reinicio completo
de Android, restauración destructiva, cambios de hora, otros SO, sincronización,
HTTP, cuentas ni tokens. Tampoco instalaciones de sistema, cambios de dependencias,
reglas de backup Android, código, PostgreSQL, commits o push.

Las 319 pruebas automatizadas y los builds web/APK son antecedentes de la entrega
E.3: no se ejecutaron nuevamente ni se confunden con estas observaciones físicas.
Los fallos FFI anteriores no acreditan durabilidad ante fallos destructivos Android.

## Git y recomendación

Se conservaron todos los cambios E.3 anteriores y .vscode/ sin seguimiento. Esta
validación agregó únicamente este documento de resultados. Al terminar la prueba
física el índice estaba vacío y HEAD permanecía f168da0, sin commit ni push.
La preparación documental posterior incluye los archivos E.3 mediante lista explícita
en el índice para revisión. El usuario autorizó posteriormente el commit exacto
y push normal de esos 14 archivos para cerrar E.3, sin tags ni releases.

Recomendación: el alcance local A/B/C está listo para revisión de cierre por el
usuario con la evidencia automatizada previa y el recorrido Android aquí observado.
La implementación y validación están completadas; el cierre E.3 fue autorizado
posteriormente por el usuario. Este cierre no amplía el alcance de lo probado.
Los límites destructivos, de respaldo permanente, otras
plataformas y sincronización permanecen explícitos; no se autoriza E.4.
