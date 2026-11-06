# Fase 3.2D — API de jardines, plantas, catálogo e historiales

Todos los endpoints siguientes requieren Authorization: Bearer con un access token
válido. No se modifica Flutter ni se implementa sincronización. El proceso reutiliza
el mismo AuthRepository/engine API existente, sin nuevas instancias de credenciales.

## Rutas

| Métodos | Ruta | Comportamiento |
| --- | --- | --- |
| POST, GET | /api/v1/gardens | Crear / listar jardines propios |
| GET, PATCH, DELETE | /api/v1/gardens/{id} | Consultar, editar, eliminar jardín vacío |
| POST, GET | /api/v1/plants | Crear / listar plantas propias |
| GET, PATCH, DELETE | /api/v1/plants/{id} | Consultar, editar, eliminar lógicamente |
| GET | /api/v1/species | Catálogo global existente, paginado |
| GET | /api/v1/species/{id} | Consultar especie existente |
| POST, GET | /api/v1/plants/{id}/growth-history | Registrar / consultar mediciones individuales |
| GET | /api/v1/growth-history | Historial de crecimiento propio, filtro plant_id opcional |
| GET | /api/v1/growth-history/{id} | Consultar una medición propia |
| POST, GET | /api/v1/plants/{id}/watering-events | Registrar / consultar riegos manuales |
| GET | /api/v1/watering-events | Historial de riegos propio, filtro plant_id opcional |
| GET | /api/v1/watering-events/{id} | Consultar evento propio |

Las respuestas GET/PATCH son 200, POST 201 y DELETE 204. El registro de cuentas
conserva su contrato anterior 202. No hay PUT ni modificación/borrado de eventos,
mediciones o catálogo. OpenAPI documenta los campos y restricciones reales.

Todos los listados devuelven `{items, total, limit, offset}`. Predeterminados:
limit=20, offset=0; máximo 100 elementos y offset 1000000. Orden de jardines/plantas
por created_at,id; catálogo por scientific_name,id; historiales por fecha medida/
ocurrida descendente y UUID descendente para desempatar. Los datos se filtran por
RLS antes de contar/paginar. Esta paginación no es un cursor de sincronización ni
una instantánea estable ante cambios concurrentes entre peticiones.

## Entradas permitidas

Los cuerpos rechazan campos desconocidos. No aceptan owner_id, created_at,
updated_at, revision, deleted_at, plant_ref_id, nombre histórico ni recorded_at.
Los UUID de recursos se generan si no se proporcionan en creación; una vez creados
no son editables. Esto prepara contratos con IDs estables sin implementar sync.

- Jardín: name obligatorio, recortado, no vacío, máximo 200; description opcional,
  máximo 4000, admite null. PATCH permite solo esos dos campos, sin nombre null.
  No hay coordenadas obligatorias. Un PATCH vacío es inválido.
- Planta: name, watering_frequency_days obligatorios. Opcionales garden_id,
  species_id, species_label (250), initial_height_m y last_watered_at inicial.
  Frecuencia entera real entre 1 y 36500; no se aceptan booleanos, fracciones o
  textos numéricos. Dimensiones numéricas en metros, positivas y finitas.
  PATCH permite esos datos excepto last_watered_at; los riegos actualizan esa fecha
  a través del endpoint manual. Campos opcionales pueden limpiarse con null.
- Crecimiento: measured_at obligatorio; height_m y diameter_m independientemente
  opcionales, con al menos uno. Si hay diámetro, diameter_kind es stem o canopy;
  no se admite tipo sin diámetro. notes opcional (4000). Nombre de planta/UUID
  histórico se toman del registro autenticado, no del cliente.
- Riego manual: occurred_at obligatorio, id opcional. event_type se fija a manual
  en el servidor. No hay cantidad de agua en el esquema aprobado: volume, litros,
  quantity y similares se rechazan; no se inventan medidas ni se añaden columnas.

Fechas de entrada: cadenas ISO 8601 con offset o Z, no timestamps numéricos ni
fechas sin zona. Se rechazan fechas futuras para mediciones, riegos y último riego
inicial; no hay tolerancia implícita al desfase de reloj. PostgreSQL usa TIMESTAMPTZ
y conexiones UTC. No se cambia el cálculo Flutter de periodos de 24 horas.

initial_height_m y last_watered_at en creación son valores iniciales de fecha/
procedencia histórica desconocida: no fabrican mediciones ni eventos. El historial
de crecimiento no sobrescribe la altura inicial. No se añade una segunda columna
editable de altura actual ni se implementa su proyección todavía. Elegir species_id
no rellena ni sobrescribe parámetros de planta. El catálogo puede estar vacío.

## Transacciones, concurrencia y borrado

ResourceRepository valida el token con auth_access y fija blueflora.owner_id de
ámbito transaccional **en la misma conexión** que opera con los recursos. Se usa
solo el rol API y las mismas políticas USING/WITH CHECK ya existentes. No se
utiliza owner_transaction de migraciones para atender peticiones.

Cada asignación de jardín comprueba visibilidad y bloquea el jardín. Las claves
compuestas siguen impidiendo asociaciones entre propietarios aunque se omitiese
una comprobación de aplicación. El jardín solo se elimina cuando no tiene ninguna
planta vinculada, incluidas las borradas lógicamente (409 si tiene referencias).
No se desvinculan o eliminan plantas automáticamente para liberar el jardín.

DELETE planta fija deleted_at, updated_at e incrementa revision; no ejecuta DELETE
SQL. Repetirlo es idempotente. GET individual de planta borrada devuelve 404; el
listado puede incluir sus tombstones con include_deleted=true. Los historiales
individuales permanecen consultables y los globales conservan plant_ref_id y el
nombre del momento del registro. No se aceptan eventos nuevos para plantas borradas.
La FK opcional de conservación histórica de 0001 no se modifica.

Registrar un riego bloquea la planta, inserta el evento y actualiza last_watered_at
solo si el evento es posterior al valor existente o este es desconocido. El cambio
incrementa revision y actualiza updated_at. Un evento antiguo se conserva sin hacer
retroceder la fecha. Ante cualquier fallo se revierte toda la transacción: no queda
un evento confirmado con una actualización de planta fallida.

Repetir el mismo UUID de riego para la misma planta y mismo instante devuelve el
evento existente sin duplicarlo ni incrementar otra vez revision. Un contenido
incompatible produce 409. Las otras creaciones con UUID duplicado producen 409;
no se implementan respuestas de sincronización ni resolución de conflictos offline.

## Permisos aprobados y errores

0003_resource_permissions concede únicamente:

- gardens: SELECT, INSERT, DELETE y UPDATE(name,description).
- plants: SELECT, INSERT y UPDATE(garden_id,species_id,name,species_label,
  initial_height_m,watering_frequency_days,last_watered_at,revision,deleted_at,updated_at).
- species: SELECT.
- growth_history y watering_events: SELECT, INSERT.

En desarrollo se conceden a blueflora_api y en pruebas a blueflora_api_test. No hay
nuevas columnas, tablas, índices, roles, funciones privilegiadas ni cambios de RLS.
No se conceden DELETE físico de plantas, escritura de catálogo, cambios de políticas,
permisos sobre auth ni privilegios por defecto para objetos futuros. Los campos
internos que SQL permite actualizar se gestionan exclusivamente desde servicios.

401: token ausente/inválido/caducado/revocado. 404 resource_not_found: identificador
inexistente, ajeno o relación no visible; no se indica cuál de ellos ocurrió.
422 invalid_request: entrada inválida, campos extra o paginación fuera de límites.
409 resource_conflict: UUID en conflicto o jardín con referencias. 503 para fallos
de almacenamiento inesperados, sin detalles SQL. Todos los errores evitan valores
secretos y las respuestas privadas incluyen Cache-Control: no-store.

## Migrar y verificar

Desde backend con el entorno virtual:

```bash
python -m app.db.manage upgrade --test
python -m pytest -q -W error
python -m app.db.manage upgrade
python -m app.db.manage current
python -m app.db.manage check-schema
python -m app.db.manage check-schema --test
```

La revisión actual esperada pasa a 0003_resource_permissions. Su downgrade solo
retira los permisos concedidos y no borra filas, columnas ni políticas; no se usa
como limpieza de datos. Las pruebas siguen aislándose en esquemas UUID efímeros
de blueflora_test y no insertan datos de demostración en desarrollo.
