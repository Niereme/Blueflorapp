# Instrucciones de trabajo en BlueFlora

Antes de comenzar, leer `docs/TRANSICION_TECNICA.md`, revisar `git status` y las
instrucciones nuevas del usuario. El resumen describe el estado, no autoriza fases
futuras. La Fase 3.2E.2 está cerrada; 3.2E.3 requiere autorización independiente.

## Alcance y cambios existentes

- Trabajar únicamente en la entrega autorizada. Conservar cambios existentes y
  pruebas anteriores; no ejecutar reset, clean, restore ni descartes sin permiso.
- No crear commits ni hacer push sin autorización explícita para la tarea actual.
  La autorización de cierre de 3.2E.2 no se extiende a commits futuros.
- Mantener `.vscode/` fuera de los commits. Preparar archivos por lista explícita;
  revisar el índice y ejecutar `git diff --cached --check` antes de cada commit.
- No versionar `.env`, credenciales, tokens, claves privadas, copias de seguridad,
  bases locales, dumps/capturas de dispositivos ni productos de compilación.
  Los ejemplos de configuración deben contener solo placeholders, nunca secretos.

## Arquitectura y datos

- Flutter funciona sin internet. La API propia utiliza FastAPI y PostgreSQL
  autohospedado; no sustituirla por Firebase, Supabase u otros servicios externos.
- Mantener separación dominio/aplicación/datos/interfaz y un controlador compartido
  de plantas. No duplicar repositorios ni convertir la UI en capa de persistencia.
- Conservar UUID, historial de plantas eliminadas y transacciones de planta+evento.
  No confirmar cambios en memoria antes de persistirlos ni truncar/transformar datos
  incompatibles silenciosamente. Mantener la regla de períodos de 24 horas.
- Un registro manual no activa bombas. No inventar humedad, sensores, eventos,
  confirmaciones físicas de agua ni apariencia de una mascota.
- No reactivar preferencias antiguas como fallback después de activar SQLite.
  Conservar origen y respaldos; la copia interna no sustituye un respaldo externo.
- SQLite de esta fase contiene exclusivamente datos anónimos; no introducir cuentas,
  contraseñas o tokens hasta autorizar su arquitectura y protección específicas.
- La política actual activa SQLite solo en Android. Los otros adaptadores y el
  diseño de sincronización no implican autorización para activarlos.

## Seguridad y entorno

- No mostrar secretos ni leer/imprimir `.env` para informes. Usar variables de
  entorno y las herramientas existentes. Mantener separadas desarrollo y pruebas.
- Backend: roles de migración separados de API, FORCE RLS, identidad autenticada
  por transacción y permisos mínimos. No ampliar roles, funciones o permisos fuera
  del alcance autorizado. Las pruebas PostgreSQL van en la base de pruebas.
- Solicitar permiso antes de otros comandos sudo, instalaciones de sistema,
  modificaciones administrativas o cambios de versiones Flutter/Dart/SDK/Gradle/
  AGP/Kotlin/dependencias. No realizar actualizaciones automáticas.
- Mantener las reglas de respaldo Android hasta recibir autorización específica.
- Antes de acciones físicas, seleccionar el dispositivo y comprobar paquete/firma.
  No desinstalar ni limpiar datos sin autorización específica. Los datos actuales
  son de prueba, pero eso no autoriza borrar información de otros proyectos/apps.
- Operar solo BlueFlora. Si el usuario está usando el teléfono u otra app está
  visible, coordinarse antes de continuar. Nunca enviar mensajes de otras apps.

## Verificación e informes

- Distinguir pruebas automatizadas, pruebas físicas y propuestas no ejecutadas.
  No repetir pruebas sin motivo ni afirmar recuperación física ante corrupción
  solo porque pasaron pruebas FFI. Documentar riesgos reales y comprobaciones pendientes.
- Para Flutter usar `flutter analyze --no-pub` y
  `bash tool/test_local_storage.sh --reporter expanded` desde `blueflora/`.
  El script FFI usa la biblioteca SQLite existente sin instalaciones ocultas.
- Para APK sin instalar componentes SDK automáticamente:
  `env 'ORG_GRADLE_PROJECT_android.builder.sdkDownload=false' flutter build apk --debug --no-pub`.
- Respetar las instrucciones más recientes del usuario si actualizan este alcance.
