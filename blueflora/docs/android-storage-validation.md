# Validación física de SQLite: procedimiento propuesto

Este procedimiento de respaldo externo completo para datos no desechables no se
ha ejecutado. Sí se realizó la validación simplificada autorizada sobre registros
de prueba del teléfono: ver [resultados](android-storage-validation-results.md).
Para futuros datos no desechables requiere dispositivo conectado, APK debug
compilado y aprobación del usuario antes de instalar/abrir la versión migradora.
No desinstalar, limpiar datos, restaurar archivos automáticamente ni cambiar las
reglas de respaldo Android. No habilita sincronización ni cuentas.

## 1. Preparar y comprobar acceso

Desde Ubuntu, seleccionar explícitamente el número de serie que aparece en
`adb devices -l`; no utilizar el primer dispositivo de manera automática:

```bash
BLUEFLORA_SERIAL='SERIAL_DEL_TELEFONO'
adb -s "$BLUEFLORA_SERIAL" shell pm path com.example.blueflora
adb -s "$BLUEFLORA_SERIAL" shell run-as com.example.blueflora pwd
```

Guardar versión de la app y copiar a Ubuntu el APK instalado (y sus splits, si
existen) usando las rutas devueltas por `pm path`. Comparar el certificado público
del APK instalado y el nuevo con `apksigner verify --print-certs` de los build-tools
existentes. Un error de firma no autoriza desinstalar ni forzar un downgrade.

Si `run-as` falla porque la versión instalada no es depurable, detenerse. No usar
root ni instalar la nueva versión para conseguir acceso: eso podría iniciar una
migración antes de haber respaldado. Acordar otro mecanismo de exportación primero.

## 2. Respaldo externo consistente, antes de actualizar o abrir el APK

Con autorización para esta comprobación, cerrar/detener la app sin borrar datos.
Guardar fuera del repositorio un archivo completo de sus datos privados. Puede
contener preferencias y otros datos personales: mantenerlo privado, no subirlo a
Git ni enviarlo por chat. Los siguientes comandos son una propuesta, NO ejecutada:

```bash
umask 077
BLUEFLORA_BACKUP_DIR="$HOME/BlueFlora-backups/$(TZ=America/Mexico_City date +%Y%m%d-%H%M%S)"
mkdir -p -- "$BLUEFLORA_BACKUP_DIR"
adb -s "$BLUEFLORA_SERIAL" shell am force-stop com.example.blueflora
adb -s "$BLUEFLORA_SERIAL" exec-out run-as com.example.blueflora tar -cf - . > "$BLUEFLORA_BACKUP_DIR/app-data.tar.partial"
```

Comprobar el código de salida de ADB y revisar el archivo antes de considerarlo
respaldo. Si falla cualquier paso, detenerse y conservar el archivo parcial para
diagnóstico; no instalar el APK. No copiar únicamente un SQLite abierto sin su
journal, sus metadatos y su comprobante de identidad.

```bash
tar -tf "$BLUEFLORA_BACKUP_DIR/app-data.tar.partial" > "$BLUEFLORA_BACKUP_DIR/manifest.txt"
mv -- "$BLUEFLORA_BACKUP_DIR/app-data.tar.partial" "$BLUEFLORA_BACKUP_DIR/app-data.tar"
sha256sum "$BLUEFLORA_BACKUP_DIR/app-data.tar" > "$BLUEFLORA_BACKUP_DIR/app-data.sha256"
sha256sum -c "$BLUEFLORA_BACKUP_DIR/app-data.sha256"
```

Ejecutar cada línea solo si la anterior terminó correctamente. Verificar en el
manifiesto que están los archivos reales de preferencias y, si ya existen, la
base SQLite, archivos auxiliares, comprobante y respaldos de migración. El archivo
completo puede incluir cachés: no implica que deban restaurarse todas las rutas.

Conservar una segunda copia verificada en un medio seguro separado del teléfono.
Un SHA-256 comprueba integridad, no cifra el respaldo ni prueba por sí solo que sea
restaurable. Registrar los recuentos actuales de plantas e historial y contrastar
UUID y campos sobre una copia privada; no imprimir el contenido personal.

## 3. Ensayar recuperación fuera del teléfono principal

Antes de migrar datos reales, ensayar lectura y recuperación en un emulador nuevo
o dispositivo de pruebas aislado. Revisar rutas del archivo y seleccionar datos
persistentes; no ejecutar una extracción indiscriminada sobre la instalación real.
Comprobar que el APK correspondiente puede leer plantas, IDs e historial recuperado.

Si falta un entorno aislado o requiere nuevos componentes SDK, solicitar autorización
antes de crearlo/instalarlos. No afirmar recuperación verificada por haber pasado
pruebas FFI: estas no equivalen a restaurar datos Android reales.

## 4. Migración y comprobaciones físicas, solo después de aprobar el respaldo

Actualizar en el dispositivo seleccionado conservando firma, paquete y datos
(`adb install -r`, sin `-d` y sin desinstalar). No ejecutar aún este paso: primero
deben haberse aprobado el respaldo y su ensayo de recuperación.

1. Abrir sin conexión y comparar plantas, UUID, nombres, especies, alturas, fechas
   y eventos con la copia previa, incluidos historiales de plantas eliminadas.
2. Confirmar que las preferencias originales siguen intactas y existe respaldo
   verificable. Confirmar la activación SQLite dentro de sus metadatos.
3. Crear una planta de prueba identificable, editarla, registrar exactamente un
   evento manual y eliminar esa planta; verificar conservación del evento.
   Hacerlo solo con autorización; no modificar ni eliminar plantas existentes.
4. Cerrar y volver a abrir; verificar persistencia, calendario de 24 horas, temas
   y recordatorios. Confirmar que registro manual no se presenta como una bomba.
5. Revisar avisos de diagnóstico/recuperación con texto 200 %, pantalla pequeña y
   teclado. Las interrupciones deliberadas y los fallos de disco deben probarse
   primero en el entorno aislado, nunca provocando corrupción en el teléfono real.

## 5. Si falla

Detener la app y capturar el estado fallido en otro respaldo, sin reemplazar el
original. Si SQLite no estaba activo, resolver la migración/reintentar manteniendo
las preferencias como origen; los datos verificables pueden mostrarse en lectura.
Si estaba activo, no volver al JSON anterior ni al APK antiguo: preservar cualquier
escritura nueva y recuperar SQLite, su identidad y metadatos como conjunto.

Cualquier restauración que sobrescriba archivos del dispositivo necesita aprobación
específica y un respaldo del estado actual. No hay en esta fase un restaurador UI
automático. El respaldo interno no protege ante desinstalación o pérdida del teléfono.
