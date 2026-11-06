# PostgreSQL local — Fase 3.2B

## Alcance y requisitos

Python 3.14.4, PostgreSQL local 18.6, SQLAlchemy 2.1.8, Psycopg 3.3.8
(con distribución binaria) y Alembic 1.20.1. El entorno virtual tiene las
versiones reproducibles en `requirements.lock`. No se instala nada globalmente.
Esta entrega no modifica Flutter ni conecta su almacenamiento a PostgreSQL.
La Fase 3.2C añade autenticación opcional con un rol de ejecución separado;
consulta [authentication.md](authentication.md). No hay sincronización.

## Recursos locales y creación inicial

El propietario de la computadora ya creó `blueflora_dev` y `blueflora_test`,
cada base con su rol homónimo. No se recrean. PostgreSQL permanece en localhost.
No se modifican servicios, pg_hba.conf ni listen_addresses desde este proyecto.

Para **otra instalación vacía**, previa autorización administrativa y después de
comprobar que los nombres no existen, un administrador puede ejecutar:

```sql
CREATE ROLE blueflora_dev LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE blueflora_test LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE DATABASE blueflora_dev OWNER blueflora_dev;
CREATE DATABASE blueflora_test OWNER blueflora_test;
```

Configurar cada contraseña de forma interactiva con `\password blueflora_dev` y
`\password blueflora_test` dentro de psql, sin contraseñas en comandos o Git.
No ejecutar estas instrucciones sobre recursos existentes. En producción se
separarán los permisos DDL de migración y DML de aplicación.

## Variables y secretos

Desde `backend/`, crear `.env` a partir de `.env.example` **solo si aún no existe**.
Mantener permisos de lectura restringidos (`chmod 600 .env`). Configurar:

- `BLUEFLORA_DATABASE_URL`: `postgresql+psycopg://blueflora_dev:CONTRASEÑA_URL@127.0.0.1:5432/blueflora_dev`.
- `BLUEFLORA_TEST_DATABASE_URL`: `postgresql+psycopg://blueflora_test:CONTRASEÑA_URL@127.0.0.1:5432/blueflora_test`.

Codificar la contraseña como componente URL (por ejemplo `@` como `%40`, `#`
como `%23`, `%` como `%25`); no codificar toda la URL ni publicarla. Las variables
exportadas prevalecen sobre `.env`. No imprimir el archivo ni poner URLs reales
en comandos compartidos. Settings usa SecretStr; las operaciones guiadas omiten
el texto de excepciones para evitar filtraciones.

La protección de esta fase exige host loopback, puerto 5432, driver psycopg,
rol y base exactos, contraseña y ausencia de parámetros alternativos de conexión.
Se valida también current_database/current_user y se rechazan superusuarios y
roles BYPASSRLS. Las credenciales de pruebas nunca heredan las de desarrollo.
No se utiliza el campo `environment` para seleccionar una base implícitamente.

## Migrar y verificar desarrollo

```bash
cd backend
source .venv/bin/activate
python -m pip install --constraint requirements.lock -e '.[test]'
python -m pip check
python -m app.db.manage check
python -m app.db.manage upgrade
python -m app.db.manage current
python -m app.db.manage check-schema
```

`upgrade` aplica las revisiones pendientes exclusivamente a `blueflora_dev.public`.
Con Fase 3.2C, `upgrade --test` prepara explícitamente `blueflora_test.public`,
con su propio rol de migración; nunca comparte el rol API ni las credenciales. No crea
bases ni roles, no inserta semillas y no se ejecuta al arrancar FastAPI. Incluye
las seis tablas y `alembic_version`. Las operaciones DDL son transaccionales;
una colisión con tablas existentes falla, sin reemplazarlas. Un segundo upgrade
es un no-op. `current` debe mostrar `0002_auth (head)` y `check-schema` debe
indicar que no hay operaciones pendientes respecto de los modelos.

Alternativa estándar desde backend: `python -m alembic upgrade head`,
`python -m alembic current` y `python -m alembic check`. No guardar sqlalchemy.url
en alembic.ini. La generación offline `python -m alembic upgrade head --sql`
no necesita credenciales ni ejecuta SQL. Revisar siempre nuevas migraciones;
no aceptar automáticamente borrados de autogenerate.

## Tablas e integridad

| Tabla | Decisiones |
| --- | --- |
| users | UUID; email normalizado único; hash opcional para cuentas reservadas; usuario inactivo por defecto. El registro autenticable exige hash Argon2id. |
| gardens | UUID; propietario obligatorio; nombre; descripción opcional; sin coordenadas. |
| species | Catálogo global opcional, sin preferencias particulares de plantas. Nombre científico único, descripción y fuente opcionales. Sin semillas ni API de edición en esta fase. |
| plants | UUID compatible con Flutter; propietario obligatorio; jardín y especie opcionales; texto libre de especie; altura inicial opcional; frecuencia entera 1–36500 días; último riego opcional; revisión positiva y borrado lógico. |
| growth_history | Propietario, UUID histórico de planta, enlace nullable, nombre histórico, altura/diámetro independientemente opcionales, instante medido y registrado, notas. Al menos una dimensión; si hay diámetro se exige tipo stem/canopy. |
| watering_events | UUID del evento; propietario; UUID histórico de planta, enlace nullable y nombre histórico; instante ocurrido/registrado; solo tipo manual. |

UUID se genera en Python cuando no se proporciona; se pueden conservar IDs
válidos recibidos de Flutter. Los nombres de plantas no son únicos. No se
convierten nombres ni posiciones en claves. Dimensiones en metros, positivas y
finitas (se rechazan NaN e infinitos), sin redondeo arbitrario. Las fechas usan
TIMESTAMPTZ; las conexiones se configuran en UTC. Un futuro importador debe exigir
instantes con offset: PostgreSQL no puede reconstruir la zona de una fecha local
sin offset emitida por versiones anteriores de Flutter. No se cambia su regla
de periodos de 24 horas ni se implementan cálculos de calendario aquí.

`initial_height_m` conserva la altura actual local de fecha desconocida, sin
fabricar una medición. Las futuras mediciones irán a growth_history; su proyección
como altura actual se implementará junto con la API, sin dos fuentes editables.
No se crea historia ficticia desde last_watered_at. El tipo JSON actual de Flutter
`manual_registration` corresponderá a `watering_events.event_type = manual`
en el futuro adaptador; no se cambia el JSON local ni se implementa aún importación. `updated_at`/`revision`
tienen valores iniciales; un futuro servicio deberá actualizarlos en sus
transacciones: no son todavía un motor de sincronización ni un trigger automático.

Cada referencia jardín/planta incluye owner_id para rechazar asociaciones entre
propietarios. Los índices cubren propietario, jardín, borrado y fechas del
historial. Los usuarios referenciados no se eliminan en cascada. Las plantas se
borrarán preferentemente de forma lógica; una eliminación física pone SOLO
plant_id a NULL, conserva owner_id, plant_ref_id y el nombre histórico. Se utiliza
`ON DELETE SET NULL (plant_id)`, disponible desde PostgreSQL 15. No se ha probado
compatibilidad con PostgreSQL anterior a 15. Una planta ya eliminada puede tener
historial importado con plant_id NULL, sin inventar una fila de planta.

El UUID primario rechaza eventos repetidos. Esto prepara idempotencia pero no
implementa todavía una respuesta HTTP idempotente ni resolución de conflictos.
Las futuras escrituras de riego deberán actualizar planta y evento en una misma
transacción; las pruebas comprueban su reversión conjunta ante un error.

## Aislamiento de propietarios

RLS habilitado y FORZADO en users, gardens, plants, growth_history y watering_events.
Una transacción debe establecer su propietario con `set_owner(connection, uuid)`
o `owner_transaction(engine, uuid)`; se usa set_config(..., true), de ámbito
transaccional. Sin contexto no se ven filas; las escrituras ajenas fallan y las
actualizaciones ajenas no afectan filas. El catálogo species es global.

El contexto **no es autenticación**: un cliente REST futuro nunca podrá elegir un
owner_id libremente. Se derivará de la identidad autenticada y validada por el
servidor. El rol SQL es exclusivo del backend; cualquiera con esas credenciales
puede cambiar el contexto o el DDL porque hoy también es propietario del esquema.
RLS no protege frente a un superusuario o un administrador que cambie políticas.
No se deben exponer las credenciales a Flutter ni Raspberry Pi. Una consulta SQL
manual sin contexto puede parecer vacía aunque existan datos.

## Pruebas aisladas y reversión

```bash
python -m pytest -q -W error
python -m pytest -m postgres -q -W error
```

Las pruebas anteriores HTTP/configuración siguen sin necesitar PostgreSQL.
Sin URL de pruebas, las pruebas PostgreSQL se marcan explícitamente como omitidas;
con URL presente, una conexión fallida o un destino equivocado es error, no skip.

Cada caso PostgreSQL conecta SOLO a blueflora_test con blueflora_test, crea un
esquema aleatorio `bf_test_<uuid>` en una transacción y ejecuta la migración real
con search_path restringido a ese esquema y pg_catalog. No migra public. Al
terminar hace ROLLBACK de DDL y datos, incluso ante un fallo. No usa TRUNCATE,
DROP DATABASE ni limpieza de objetos anteriores. Un caso verifica downgrade y
upgrade exclusivamente dentro de su propio esquema transaccional; esto no altera
la revisión persistente de la base de pruebas. Las pruebas de autenticación posteriores usan un esquema efímero confirmado
para permitir conexiones concurrentes del rol API y lo retiran al terminar.
La CLI admite --test únicamente para la base blueflora_test autorizada.

La reversión de la migración inicial elimina las seis tablas y sus datos. **No
se ejecuta sobre desarrollo en esta entrega.** Para una reversión manual futura,
primero revisar dependencias, obtener y comprobar una copia de seguridad y contar
con autorización explícita. El comando requiere una confirmación deliberada:

```bash
python -m alembic -x allow_destructive_downgrade=true downgrade base
```

No usarlo como rutina de limpieza ni en bases con información que deba conservarse.
Una migración fallida antes del COMMIT se revierte transaccionalmente; una ya
confirmada debe corregirse mediante otra revisión o restauración planificada.
