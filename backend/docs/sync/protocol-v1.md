# Protocolo offline-first v1 — contrato normativo propuesto

**No implementado.** Este contrato requiere aprobación antes de cambiar 3.2D.
Los UUID de ejemplo son ficticios. Los identificadores opacos demo son etiquetas
de documentación, no credenciales ni cursores aceptados por un servidor real.
Push/changes y bootstrap ilustran escenarios independientes; los pasos de import
sí comparten el mismo manifiesto, registros e identificadores.

## 1. Reglas comunes

- HTTPS obligatorio fuera de pruebas locales loopback. Authorization: Bearer con
  access token válido en TODOS los endpoints, incluidas páginas y estado import.
  Nunca tokens en JSON, URL, SQLite, logs o capturas de errores.
- JSON UTF-8, Content-Type application/json. Content-Encoding distinto de identity
  se rechaza con 415 en v1. Se limita el cuerpo antes de deserializarlo.
- Respuestas privadas: Cache-Control: no-store. Logs excluyen cuerpos, cabeceras
  Authorization y valores de cursores; se permiten códigos y correlation_id.
- protocol_version=1. No hay campos owner_id/user_id editables: el sujeto surge de
  auth_access y se fija con set_config(...,true) en la transacción de escritura.
- installation_id UUID identifica la instalación de app, NO un jardín ni hardware
  ni una credencial. Se registra bajo el sujeto al primer bootstrap; un UUID ya
  asignado a otra cuenta devuelve 409 identity_unavailable, sin indicar a quién.
  Cada espacio de cuenta genera su installation_id; no se comparte entre cuentas.
- UUID se transporta en minúsculas con guiones. Revisiones y secuencias son cadenas
  decimales canónicas positivas, sin signo/ceros iniciales, hasta 9223372036854775807.
  El cero solo se admite como secuencia inicial. No usar números JS para BIGINT.
- Instantes: RFC3339 con offset/Z, precisión máxima microsegundos, salida UTC Z.
  Sin timestamps numéricos ni valores NaN/Infinity. Una hora futura se rechaza con
  timestamp_in_future y server_time; NO se corrige automáticamente. Solo tras
  corregir el reloj puede reintentarse como nueva operación si hubo rechazo final.
- Longitudes en puntos de código Unicode, no bytes ni unidades UTF-16. Mantener
  texto exacto, salvo trim de nombres NUEVOS según el contrato de UI. No normalizar
  acentos, truncar ni convertir especie libre a species_id por coincidencia.
- Campos desconocidos/duplicados, claves JSON duplicadas, null en obligatorios y
  estructuras demasiado profundas se rechazan; profundidad máxima 16.
- JCS RFC 8785 + SHA-256 determina fingerprints. Primero validar y convertir UUID,
  instantes y revisiones a su representación canónica; payload resultante es el
  mismo enviado a todos los reintentos. No ordenar listas que sean significativas.
  No usar json.dumps genérico como sustituto sin verificar vectores JCS. El hash
de operación incluye protocol_version y los seis campos de la operación, no el
access token ni la installation_id del envelope; una recuperación autorizada de
la misma cuenta puede consultar el mismo recibo desde una instalación nueva.
- Los cursores son opacos autenticados y ligados al sujeto, installation_id,
  server_instance_id, época y tipo de consulta. No conceden autorización por sí
  mismos. 404 genérico si pertenecen a otra cuenta/instalación; no revelar su origen.
- server_instance_id es UUID público y estable del despliegue, distinto de la URL.
  El futuro /me lo anunciará. Un cambio de instancia no reutiliza cursores, cuentas
  ni colas automáticamente, aunque el user_id coincida.

### Límites

| Elemento | Límite v1 |
| --- | --- |
| Cuerpo de POST | 512 KiB UTF-8, sin compresión |
| Respuesta push/import | Máximo 4 MiB; hasta 50 recibos/grupos de 64 KiB |
| Operaciones push / registros stage | 1–50 |
| Operación o registro individual canónico | 64 KiB |
| Dependencias por operación | 0–16 |
| Página changes | 1–100 grupos, máximo 1 MiB de JSON serializado |
| Grupo incremental | Máximo 4 entidades, 64 KiB; nunca se divide |
| Página bootstrap | 1–100 entidades, máximo 1 MiB |
| Cursor | Máximo 2048 caracteres |
| Importación | 100000 registros y 64 MiB canónicos acumulados |
| Bootstrap fijo | 50000 registros y 64 MiB; si excede, 413 sin snapshot parcial |
| Snapshots/importaciones staged activos | Máximo 2 de cada tipo por cuenta |
| TTL bootstrap / staging de import | 24 horas desde creación, sin extensión por lectura |

Un límite de página no obliga a devolver el máximo de elementos. Un registro que
por sí solo exceda su límite produce error explícito, nunca se omite. Los DTO de
campos acotados deben caber en 64 KiB, incluyendo su envoltorio. No permitir listas
arbitrarias en una sola mutación. El bootstrap no usa una conexión SQL abierta a
través de varias peticiones HTTP. Sin purgas de recibos de operaciones en v1.

### Errores HTTP comunes

Formato uniforme, sin payload sensible:

```json
{
  "detail": {
    "code": "invalid_request",
    "message": "Revisa los campos de la solicitud.",
    "fields": [{"path": "operations[0].entity_id", "code": "invalid_uuid"}],
    "retryable": false,
    "correlation_id": "90000000-0000-4000-8000-000000000001"
  }
}
```

| HTTP | Código / acción |
| --- | --- |
| 400 | unsupported_protocol, invalid_cursor; no mutaciones |
| 401 | authentication_failed; renovar una vez de forma coordinada o solicitar login |
| 404 | resource_not_found; sesión/snapshot/cursor ajeno o inexistente indistinguibles |
| 409 | identity_unavailable, manifest_mismatch, import_not_ready, resolution_required |
| 410 | cursor_expired, bootstrap_expired, import_expired; recuperación explícita |
| 413 | request_too_large, record_too_large, snapshot_too_large |
| 415 | unsupported_media_type o compresión no admitida |
| 422 | invalid_request estructural; petición no procesada |
| 429 | rate_limited; respetar Retry-After, no borrar cola |
| 503 | service_unavailable; reintento con backoff y jitter |

En push los conflictos/validaciones semánticas POR OPERACIÓN van en un HTTP 200,
no se confunden con aceptación de todas. Un corte puede ocurrir tras cualquier
COMMIT, incluso si HTTP termina en 401/503 o no llega: resolver por recibos, nunca
suponer que todo falló. No reintentar automáticamente un refresh incierto.

## 2. DTO de entidades y acciones admitidas

Las imágenes de servidor incluyen todos los campos propios del tipo, incluso
nulls, para que el móvil preserve campos que su UI todavía no edita. El servidor
no transmite hashes de autenticación. Las revisiones son del estado remoto,
independientes de local_version y de secuencia de cambios.

| Tipo | Campos de estado (además de id/revision) |
| --- | --- |
| garden | name, description, created_at, updated_at, deleted_at |
| plant | garden_id, species_id, name, species_label, initial_height_m, baseline_last_watered_at, baseline_source, last_watered_at, created_at, updated_at, deleted_at |
| plant (continuación) | watering_frequency_days |
| plant_reference | state=historical_only, deleted_at=null; identidad real previamente referenciada, sin nombre/especie ficticios |
| watering_event | plant_ref_id, plant_id nullable, plant_name_snapshot, occurred_at, recorded_at, event_type=manual |
| growth_measurement | plant_ref_id, plant_id nullable, plant_name_snapshot, measured_at, recorded_at, height_m, diameter_m, diameter_kind, notes |
| species | scientific_name, common_name, description, source; sin revisión por usuario |

plant_reference no se crea desde push normal: solo importación. Una planta completa
borrada sigue teniendo su estado con deleted_at, no se degrada a una referencia.
Eventos/mediciones son append-only en v1, revisión "1". No hay corrección silenciosa,
borrado ni edición de historia; una futura rectificación requerirá nuevo contrato.

Acciones push:

| Acción | payload permitido | base_revision |
| --- | --- | --- |
| garden.create | name, description opcional | null |
| garden.update | patch no vacío: name y/o description | obligatoria |
| garden.delete | objeto vacío; archiva sin desvincular plantas | obligatoria |
| plant.create | name, watering_frequency_days; opcionales garden_id, species_id, species_label, initial_height_m, baseline_last_watered_at | null |
| plant.update | patch no vacío de esos campos EXCEPTO baseline_last_watered_at | obligatoria |
| plant.delete | objeto vacío; tombstone | obligatoria |
| watering_event.create | plant_ref_id, plant_name_snapshot, occurred_at | null |
| growth_measurement.create | plant_ref_id, plant_name_snapshot, measured_at, height_m/diameter_m/diameter_kind/notes | null |

El entity_id es obligatorio en todas las creaciones. baseline_source es unknown
si el baseline es null; declared_initial al crear uno nuevo con fecha. El import
permite además legacy_snapshot/legacy_registration cuando hay procedencia explícita. El backend determina owner, recorded_at, revisiones y fechas de modificación.
Push exige plant_name_snapshot capturado al registrar el hecho offline: es texto
declarado por su propietario, no evidencia verificada del nombre en esa fecha.
No se reemplaza por el nombre actual al llegar. El REST normal 3.2D conserva su
regla de tomar el nombre actual; no confundir ambos contratos.
No aceptar last_watered_at derivado, revision, deleted_at, created_at ni tipo de
hardware en payload. Límites de 3.2D: name/snapshot 200, especie libre 250,
description/notes 4000, frecuencia entera 1–36500, dimensiones finitas >0 metros;
altura/diámetro independientes con al menos uno y tipo stem/canopy si hay diámetro.
Campos opcionales omitidos se conservan en update; null los limpia. No nombre ni
frecuencia null. Un jardín archivado conserva asignaciones existentes, pero no
acepta nuevas asignaciones. Elegir species_id jamás cambia preferencias de planta.

Un evento offline para una planta propia ya borrada SE CONSERVA como historia:
se usa el tombstone y no se restaura la planta. Una referencia inexistente no se
adivina ni crea desde push (rechazo); usar el flujo de importación histórica.
Un riego de planta borrada no modifica su calendario; si está activa se proyecta
max(baseline, eventos aceptados). Dos dispositivos con riegos distintos conservan
ambos. Si el borrado y un riego llegan en cualquier orden, ambos quedan registrados.
El snapshot de nombre enviado en push se valida (no vacío, máximo 200) después
de validar la referencia propia, y queda inmutable. Import se reserva al legado y
la vinculación voluntaria, no se exige una importación nueva por cada riego offline.

## 3. POST /api/v1/sync/push

Authorization Bearer. envelope: protocol_version, installation_id, change_epoch y operations.
Operación: operation_id, action, entity_id, base_revision, depends_on, payload.
Sin campos adicionales. Cada operación tiene recibo por (sujeto,operation_id).

Solicitud completa de edición:

```json
{
  "protocol_version": 1,
  "installation_id": "10000000-0000-4000-8000-000000000001",
  "operations": [
    {
      "operation_id": "20000000-0000-4000-8000-000000000001",
      "action": "plant.update",
      "entity_id": "30000000-0000-4000-8000-000000000001",
      "base_revision": "7",
      "depends_on": [],
      "payload": {
        "name": "Lavanda del patio"
      }
    }
  ],
  "change_epoch": "c0000000-0000-4000-8000-000000000001"
}
```

Respuesta 200 completa:

```json
{
  "protocol_version": 1,
  "server_instance_id": "a0000000-0000-4000-8000-000000000001",
  "server_time": "2026-11-06T12:00:00Z",
  "results": [
    {
      "operation_id": "20000000-0000-4000-8000-000000000001",
      "status": "applied",
      "replayed": false,
      "receipt": {
        "committed_sequence": "42",
        "entities": [
          {
            "entity_type": "plant",
            "entity_id": "30000000-0000-4000-8000-000000000001",
            "revision": "8",
            "state": {
              "id": "30000000-0000-4000-8000-000000000001",
              "name": "Lavanda del patio",
              "garden_id": null,
              "species_id": null,
              "species_label": "Lavanda",
              "initial_height_m": 1.5,
              "watering_frequency_days": 3,
              "baseline_last_watered_at": null,
              "baseline_source": "unknown",
              "last_watered_at": null,
              "created_at": "2026-11-01T12:00:00Z",
              "updated_at": "2026-11-06T12:00:00Z",
              "deleted_at": null
            }
          }
        ]
      }
    }
  ],
  "change_epoch": "c0000000-0000-4000-8000-000000000001"
}
```

Procesamiento:

1. Validar tamaño/envelope, UUID, acciones, número de elementos y dependencias sin
   ciclos antes de procesar ninguna operación; operation_id repetido en el lote es inválido. Fallo estructural: 422, ninguna.
2. Procesar en el orden del array; cada operación tiene su transacción. No hay
   atomicidad de todo el lote. Una dependencia puede referir un recibo anterior
   o una operación ya aplicada del mismo lote, nunca una posterior.
3. Validar token y rol API; bloquear estado sync del propietario; consultar recibo.
   Mismo operation_id+fingerprint devuelve el recibo original (replayed=true),
   ANTES de volver a comprobar la revisión actual. Otra huella: rejected con
   operation_id_reused; jamás sustituye el recibo previo.
4. Validar payload semántico, relaciones y revisión; confirmar datos, recibo y
   grupo incremental JUNTOS. Si falla, ninguno de esos tres queda parcial.
5. Resultado por operación: applied, conflict, rejected o blocked. conflict y
   rejected son terminales y se conservan, sin cambio incremental si no mutaron.
   blocked no es terminal y no crea recibo ni consume revisión.

change_epoch debe coincidir con la época actual. Si no, HTTP 409 epoch_mismatch
antes de aplicar nuevas operaciones; no cambiarla automáticamente en un request
congelado. Un bootstrap nuevo conduce a reconciliación explícita, conservando ACK
y datos locales que una restauración pudo perder. La época no forma parte del hash
de intención, pero una operación antigua no se reautoriza solo cambiando su envelope.
Para una cuenta nueva se requiere bootstrap antes del primer push: registra la
instalación y valida protocolo. Anónimo nunca llama push.

Conflicto propio de revisión, HTTP 200 (fragmento de results):

```json
{
  "operation_id": "20000000-0000-4000-8000-000000000001",
  "status": "conflict",
  "replayed": false,
  "error": {"code": "revision_conflict", "retryable": false},
  "server_revision": "9",
  "changed_fields": ["name"],
  "server_state": {
    "id": "30000000-0000-4000-8000-000000000001",
    "name": "Lavanda de la terraza",
    "garden_id": null,
    "species_id": null,
    "species_label": "Lavanda",
    "initial_height_m": 1.5,
    "watering_frequency_days": 3,
    "baseline_last_watered_at": null,
    "baseline_source": "unknown",
    "last_watered_at": null,
    "created_at": "2026-11-01T12:00:00Z",
    "updated_at": "2026-11-06T11:59:00Z",
    "deleted_at": null
  }
}
```

changed_fields puede ser null si el servidor no dispone del detalle desde esa
revisión; es informativo; la comparación usa la base almacenada en el móvil.
Solo devolver server_state cuando pertenece al sujeto. Identificador ausente/ajeno
produce rejected resource_not_found sin estado. Conflicto de identidad global
produce rejected identity_unavailable, sin informar si la causa es otro propietario.
Semántica inválida: rejected invalid_payload con paths/códigos sin valores originales.
Dependencia aún no aplicada: blocked dependency_unsatisfied, retryable=true; si
requiere resolver un conflicto terminal: blocked dependency_requires_resolution,
retryable=false. Si no hubo cambio nuevo, receipt.committed_sequence puede ser null y entities
contiene el estado propio reconocido. No se fabrica un grupo vacío. No repetir un rechazo final esperando que cambie su resultado:
resolver como nueva operación que supersede a la anterior, conservando ambas.

El mismo UUID de entidad con otro operation_id no fusiona creaciones: conflict
entity_exists si es propio; identity_unavailable si no se puede usar. UUID de
riego/medición redundante y contenido semántico idéntico se reconoce como efecto
ya presente, sin segundo evento ni nuevo incremento; diferente contenido: conflict
entity_content_mismatch. Fingerprint de evento incluye tipo, planta, instante y
snapshot declarado original congelado al aceptar el hecho; el reintento de la misma
operación nunca recalcula ese snapshot con un nombre actual.

El cliente mantiene orden por entidad. Antes del primer envío fija base_revision
del último ACK conocido; solo una operación de esa entidad puede estar en vuelo.
Una segunda edición creada entretanto queda durable como borrador dependiente y
se congela después. Desde el primer intento nunca cambiar los seis campos de la operación ni su hash.
Renovar el token de transporte no cambia la intención. Restaurar en otra instalación
requiere autenticar al mismo sujeto/instancia; un cambio de época requiere resolución,
no un reintento automático con otro envelope raíz.
Backoff para fallos transitorios: 1,2,4,... hasta 300 segundos más jitter 0–20%;
Retry-After prevalece. Una confirmación es durable localmente junto con shadow y
estado outbox. committed_sequence NO autoriza avanzar el cursor de descarga.

## 4. GET /api/v1/sync/changes

GET no lleva JSON de solicitud. Parámetros: cursor requerido, limit=50 (1–100).
Ejemplo: `/api/v1/sync/changes?cursor=cur_demo_041&limit=50`.
Authorization Bearer; la instalación se recupera del cursor autenticado.
No offset, owner, filtros de entidad ni fecha.

```json
{
  "protocol_version": 1,
  "server_instance_id": "a0000000-0000-4000-8000-000000000001",
  "server_time": "2026-11-06T12:00:00Z",
  "catalog_version": "1",
  "changes": [
    {
      "sequence": "42",
      "change_id": "b0000000-0000-4000-8000-000000000001",
      "operation_id": "20000000-0000-4000-8000-000000000001",
      "entities": [
        {
          "entity_type": "plant",
          "entity_id": "30000000-0000-4000-8000-000000000001",
          "revision": "8",
          "state": {
            "id": "30000000-0000-4000-8000-000000000001",
            "name": "Lavanda del patio",
            "garden_id": null,
            "species_id": null,
            "species_label": "Lavanda",
            "initial_height_m": 1.5,
            "watering_frequency_days": 3,
            "baseline_last_watered_at": null,
            "baseline_source": "unknown",
            "last_watered_at": null,
            "created_at": "2026-11-01T12:00:00Z",
            "updated_at": "2026-11-06T12:00:00Z",
            "deleted_at": null
          }
        }
      ]
    }
  ],
  "window_end_sequence": "42",
  "has_more": false,
  "next_cursor": "cur_demo_042",
  "change_epoch": "c0000000-0000-4000-8000-000000000001"
}
```

HTTP 200 incluso si changes=[]; conservar un cursor válido en ambos casos. Un
cursor abre una ventana hasta el head confirmado; páginas intermedias mantienen
ese corte. El cursor de cola final permite abrir la siguiente ventana. Repetir una
lectura en la cola puede incluir cambios nuevos: es lectura idempotente, no promesa
de bytes idénticos eternamente. Grupos existentes por secuencia son inmutables.
Páginas no parten grupos; el límite de bytes puede acortar la cantidad. Los cambios
contienen imágenes completas, incluidos tombstones, no solo IDs para un GET que
podría cambiar entre lecturas. Un grupo de riego contiene evento y planta derivada
si esta cambió. Cambios REST también entran aquí.

Aplicar página + cambios de shadow + conflictos + cursor en UNA transacción local.
Deduplicar por (espacio,época,secuencia) y revisión, sin sobrescribir un shadow más
nuevo con el ACK antiguo de una operación. Al interrumpirse antes del COMMIT se
relee la página; después del COMMIT se usa next_cursor. No saltar páginas propias.

400 si cursor malformado; 404 si ajeno; 410 si época no disponible (no purga por
antigüedad en v1, pero puede cambiar tras una restauración administrativa). Ante
410 se inicia bootstrap, manteniendo outbox/conflictos. Si cambia catalog_version,
obtener un bootstrap nuevo para refrescar el catálogo fijo, preservando cambios
locales. El catálogo global no comparte el contador privado del usuario.

## 5. POST /api/v1/sync/bootstrap

Authorization Bearer. Creación idempotente por (sujeto,bootstrap_id).

```json
{
  "protocol_version": 1,
  "installation_id": "10000000-0000-4000-8000-000000000001",
  "bootstrap_id": "70000000-0000-4000-8000-000000000001",
  "page_size": 100
}
```

```json
{
  "protocol_version": 1,
  "server_instance_id": "a0000000-0000-4000-8000-000000000001",
  "bootstrap_id": "70000000-0000-4000-8000-000000000001",
  "status": "ready",
  "created_at": "2026-11-06T12:00:00Z",
  "expires_at": "2026-11-07T12:00:00Z",
  "snapshot_sequence": "42",
  "catalog_version": "1",
  "record_count": 1,
  "first_page_cursor": "page_demo_000",
  "base_cursor": "cur_demo_042",
  "change_epoch": "c0000000-0000-4000-8000-000000000001"
}
```

201 primera creación; 200 repetición idéntica; 409 request_id_reused si cambian sus
parámetros. Si expiró, 410 (nuevo bootstrap_id explícito). page_size 1–100 y queda
fijo. La respuesta se publica solo tras copiar consistentemente datos, catálogo y
corte del contador; aislamiento snapshot y bloqueo por propietario, con reintento
interno ante conflictos de serialización. Payloads se materializan en PostgreSQL;
no una transacción/conexión abierta durante 24h. No implica bloquear ediciones
mientras se descargan páginas. No inserta datos de jardín/planta del usuario.
Si se exceden cuotas/límites: 429/413, sin snapshot parcial. Lecturas no alargan TTL.

### GET /api/v1/sync/bootstrap/{bootstrap_id}/pages

GET sin cuerpo JSON. Requiere `cursor=page_demo_000`; tamaño ya fijado por POST.
Authorization Bearer, misma cuenta e instalación. No paginar con offset/IDs vivos.

```json
{
  "protocol_version": 1,
  "bootstrap_id": "70000000-0000-4000-8000-000000000001",
  "page_index": 0,
  "records": [
    {
      "entity_type": "garden",
      "entity_id": "40000000-0000-4000-8000-000000000001",
      "revision": "1",
      "state": {
        "id": "40000000-0000-4000-8000-000000000001",
        "name": "Patio",
        "description": null,
        "created_at": "2026-11-01T12:00:00Z",
        "updated_at": "2026-11-01T12:00:00Z",
        "deleted_at": null
      }
    }
  ],
  "has_more": false,
  "next_page_cursor": null,
  "snapshot_sequence": "42",
  "base_cursor": "cur_demo_042",
  "change_epoch": "c0000000-0000-4000-8000-000000000001"
}
```

HTTP 200. El conjunto tiene orden fijo: catálogo, jardines, referencias de plantas,
plantas, eventos y crecimiento; dentro de tipo por UUID. Incluye referencias
históricas, plantas/jardines archivados y catálogo global. Relaciones se aplican al
activar todo el snapshot; no exigir que cada página aislada sea una base completa.
GET del mismo cursor da el mismo contenido hasta su vencimiento. 404 para IDs ajenos,
400 para cursor inválido, 410 al vencer. Un snapshot vacío sigue dando una página
vacía final; nunca significa borrar datos locales.

Guardar páginas en staging local idempotente por bootstrap_id/page_index. Verificar
completitud contra record_count, UUID únicos y relaciones; activar shadows+base_cursor
en una transacción, rebasando comandos locales. La respuesta incluye change_epoch explícito: no extraerlo analizando el cursor.
El base_cursor NO se activa antes
de completar la instantánea. Conservar proyección y conflictos locales si faltan
registros remotos inesperadamente; ausencia no se convierte en eliminación.

## 6. POST /api/v1/sync/import

Ruta única con action: prepare, stage, commit, status o cancel. Authorization Bearer.
Requiere instalación registrada y consentimiento explícito obtenido por Flutter.
El servidor valida consentimiento declarado, no puede demostrar cómo se presentó
la pantalla: la app debe registrar qué selección y versión confirmó la persona.

### prepare — crear manifiesto, no publicar entidades

```json
{
  "protocol_version": 1,
  "installation_id": "10000000-0000-4000-8000-000000000001",
  "action": "prepare",
  "request_id": "d0000000-0000-4000-8000-000000000001",
  "import_id": "60000000-0000-4000-8000-000000000001",
  "consent": {
    "version": "link-local-v1",
    "confirmed": true
  },
  "manifest": {
    "format": "blueflora-import-v1",
    "record_count": 2,
    "counts": {
      "garden": 0,
      "plant": 0,
      "plant_reference": 1,
      "watering_event": 1,
      "growth_measurement": 0
    },
    "content_sha256": "025e5566bdad4cf0a3287ca9e5faac764a2564830f012d53259d350402d62075"
  },
  "change_epoch": "c0000000-0000-4000-8000-000000000001"
}
```

El hash de este ejemplo está calculado sobre los dos registros stage mostrados
abajo; no copiarlo para otros datos. La implementación debe calcular cada manifiesto.
prepare exige change_epoch actual; el plan queda ligado a ella. Un cambio de
época durante staging/publicación bloquea nuevos commits con 409 epoch_mismatch,
conservando recibos previos para recuperación. status puede informar la época
antigua y atención requerida, sin autorizar publicación en la nueva.
El manifiesto abarca SOLO los elementos seleccionados: hash de concatenar, por
record_index ascendente, JCS del registro completo + byte LF. No subir el backup
crudo ni tokens, datos excluidos o preferencias. consent=false se rechaza con 422.
No se confía en una hora de consentimiento del dispositivo para ordenar nada.

```json
{
  "protocol_version": 1,
  "import_id": "60000000-0000-4000-8000-000000000001",
  "status": "staging",
  "expires_at": "2026-11-07T12:00:00Z",
  "received_count": 0,
  "applied_count": 0,
  "next_record_index": 0
}
```

201 al crear, 200 replay. Mismo import_id y manifiesto incompatible: 409.
(request_id,sujeto) fija el hash de la acción; no se reutiliza para otra acción.

### stage — segmentos contiguos, validados y sin efectos de negocio

```json
{
  "protocol_version": 1,
  "installation_id": "10000000-0000-4000-8000-000000000001",
  "action": "stage",
  "request_id": "d0000000-0000-4000-8000-000000000002",
  "import_id": "60000000-0000-4000-8000-000000000001",
  "records": [{
    "record_index": 0,
    "operation_id": "20000000-0000-4000-8000-000000000010",
    "entity_type": "plant_reference",
    "entity_id": "30000000-0000-4000-8000-000000000099",
    "payload": {"state": "historical_only"}
  }, {
    "record_index": 1,
    "operation_id": "20000000-0000-4000-8000-000000000011",
    "entity_type": "watering_event",
    "entity_id": "50000000-0000-4000-8000-000000000001",
    "payload": {
      "plant_ref_id": "30000000-0000-4000-8000-000000000099",
      "plant_name_snapshot": "Albahaca de la ventana",
      "occurred_at": "2026-10-01T18:00:00Z",
      "event_type": "manual"
    }
  }]
}
```

```json
{
  "protocol_version": 1,
  "import_id": "60000000-0000-4000-8000-000000000001",
  "status": "validated",
  "received_count": 2,
  "applied_count": 0,
  "next_record_index": 2,
  "issues": []
}
```

200. Índices 0..record_count-1 únicos; segmentos empiezan en next_record_index o
repiten un segmento ya idéntico. Otro contenido para un índice/request_id: 409.
Orden del manifiesto: jardines, referencias, plantas, eventos, crecimiento; UUID
ascendente dentro de tipo. Una referencia no se duplica si hay planta completa.
Si hay errores semánticos se guarda staging con issues por índice/código/path y
status=needs_review; no truncar ni aplicar una parte del segmento. Un documento
estructural inválido produce 422 sin guardar el segmento. Al recibir todo comprobar
hash/recuentos y dependencias; validated solo si todo coincide y es válido.

Payload de plant admite los campos de plant.create, pero baseline_source es
obligatorio: legacy_registration, legacy_snapshot o declared_initial. Campos
last_watered_at de Flutter se convierten a baseline_last_watered_at, no a eventos.
Registros importados de crecimiento y riego conservan plant_name_snapshot
original, igual que push. El endpoint REST normal lo toma del estado actual. Fechas ya deben estar resueltas explícitamente en el móvil.
Import admite los mismos campos de crecimiento/riego de push, sin exigir que
la planta siga activa y permitiendo resolver primero una referencia histórica.
No aceptar raw_json, fuentes de credenciales ni históricos artificiales. Un nombre
histórico original válido se conserva exactamente. Referencia historical_only no
crea fila plants, ni deleted_at ficticio, ni restaura una planta remota.

### commit — publicación por registros, con progreso y reintentos

```json
{
  "protocol_version": 1,
  "installation_id": "10000000-0000-4000-8000-000000000001",
  "action": "commit",
  "request_id": "d0000000-0000-4000-8000-000000000003",
  "import_id": "60000000-0000-4000-8000-000000000001",
  "max_records": 50
}
```

```json
{
  "protocol_version": 1,
  "import_id": "60000000-0000-4000-8000-000000000001",
  "status": "completed",
  "received_count": 2,
  "applied_count": 2,
  "remaining_count": 0,
  "blocked_indices": [],
  "results": [{
    "record_index": 0,
    "operation_id": "20000000-0000-4000-8000-000000000010",
    "status": "applied",
    "committed_sequence": "43"
  }, {
    "record_index": 1,
    "operation_id": "20000000-0000-4000-8000-000000000011",
    "status": "applied",
    "committed_sequence": "44"
  }]
}
```

max_records 1–50, no exceder límites de respuesta. 200 completed; 202 applying si
quedan registros; 409 resolution_required si una concurrencia genera conflicto,
con progreso y blocked_indices, sin estado ajeno. Antes de publicar debe existir
validated. Cada registro tiene datos+recibo+grupo transaccional y se aplica en orden
causal. Un mismo commit request_id devuelve su respuesta histórica aunque el
trabajo avance después; usar nuevo request_id para el siguiente tramo.

Revisar colisiones y relaciones de nuevo al aplicar: stage no reserva recursos de
otra cuenta ni bloquea la cuenta durante 24h. Una planta remota propia existente
NO se sobrescribe al importar: si coincide exactamente se enlaza; si difiere,
conflicto con resolución explícita. Colisiones ajenas: identity_unavailable sin
metadatos. Un evento idéntico ya propio puede reconocerse sin duplicación.

### status / cancel

```json
{
  "protocol_version": 1,
  "installation_id": "10000000-0000-4000-8000-000000000001",
  "action": "status",
  "import_id": "60000000-0000-4000-8000-000000000001",
  "after_record_index": -1,
  "limit": 50
}
```

200: mismo resumen de progreso más results de recibos por record_index ascendente,
limit 1–50 y next_after_record_index (null al terminar). Lectura actual: puede
avanzar entre consultas. No muta negocio. Una interrupción de stage/commit se
recupera leyendo estado y/o repitiendo el request_id original. 404 si import ajeno.

Cancel usa action=cancel, request_id nuevo y el mismo import_id/installation_id.
200 con status=cancelled y contadores de aplicados/no aplicados. Cancela SOLO los
pendientes; no revierte ni borra registros ya publicados. Repetirlo es idempotente.
Si ya completed devuelve completed. Cancelled no vuelve a commit; una nueva
selección requiere un nuevo import_id y consentimiento.

Staging expira a las 24h; comenzar commit antes del vencimiento fija un plan de
aplicación durable sin ese TTL (no puede perderse a mitad de publicación). Datos
staged expirados sin publicación no se borran del móvil: 410 solicita nuevo plan.
Recibos/progreso de completed, cancelled o attention_required se conservan en v1.
Ante conflicto durante publicación status=attention_required. Nada ya aplicado se
repite; pendientes se resuelven en un nuevo plan explícito. Después de un import, sus resultados resumen confirman recibos pero no contienen
la base completa de futuras ediciones: mantener los borradores dependientes hasta
que changes haya descargado sus grupos y revisiones, sin bloquear edición offline.
Nunca declarar éxito
completo si quedan registros, ni activar cursor desde un resultado import/push.

## 7. Compatibilidad REST y resolución

Todas las mutaciones REST y sync deben llamar al mismo servicio transaccional,
con mismo contador, reglas y ledger. Para habilitar múltiples dispositivos es
obligatorio aprobar transición del REST 3.2D: ETag fuerte en lecturas, If-Match
obligatorio en PATCH/DELETE (428 ausente, 412 no coincide); Idempotency-Key UUID en
POST, mismo namespace de operation_id. GET/listados actuales siguen disponibles;
no sirven de cambios incrementales. DELETE garden pasa a archivado en contrato
nuevo, no borrado físico. No cambiar estos contratos silenciosamente en producción.
Esta ruptura deliberada requiere aprobación y actualización de pruebas de contrato,
conservando toda la cobertura de 3.2D antes de activar sincronización.

Comparación base/local/remoto: comparar campos editables; las proyecciones
derivadas de riegos no se envían como un patch de perfil. Campos distintos pueden combinarse solo si el estado
resultante valida relaciones y se vuelve a escribir con revisión remota actual,
como NUEVA operación. Campos iguales en ambos lados no son conflicto. Cambios
distintos del mismo campo, edición contra tombstone y colisiones de identidad
requieren decisión visible. No existe restore ni transferencia entre propietarios
en v1; una restauración por copia voluntaria genera nueva identidad. Un conflicto
no borra el borrador, eventos, recibos ni la base usada para compararlos.

Referencia de canonicalización: [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785).

### Ejemplos completos de status y cancel

Respuesta 200 a status para la importación completada del ejemplo:

```json
{
  "protocol_version": 1,
  "import_id": "60000000-0000-4000-8000-000000000001",
  "status": "completed",
  "received_count": 2,
  "applied_count": 2,
  "remaining_count": 0,
  "blocked_indices": [],
  "results": [
    {"record_index": 0, "operation_id": "20000000-0000-4000-8000-000000000010", "status": "applied", "committed_sequence": "43"},
    {"record_index": 1, "operation_id": "20000000-0000-4000-8000-000000000011", "status": "applied", "committed_sequence": "44"}
  ],
  "next_after_record_index": null
}
```

Cancelar una importación ya completada es un no-op, no un borrado:

```json
{
  "protocol_version": 1,
  "installation_id": "10000000-0000-4000-8000-000000000001",
  "action": "cancel",
  "request_id": "d0000000-0000-4000-8000-000000000004",
  "import_id": "60000000-0000-4000-8000-000000000001"
}
```

```json
{
  "protocol_version": 1,
  "import_id": "60000000-0000-4000-8000-000000000001",
  "status": "completed",
  "applied_count": 2,
  "remaining_count": 0,
  "cancelled_pending_count": 0
}
```

En una cancelación parcial, status=cancelled y cancelled_pending_count indica
cuántos registros dejaron de ser elegibles; applied_count no disminuye. remaining_count
se refiere a registros aún sin publicar, aunque estén cancelados. Nunca convertir
cancelled_pending_count en un borrado remoto ni descartar sus datos locales.
