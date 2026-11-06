# BlueFlora — Backend, Fase 3.2C

Base independiente de Flutter con FastAPI y configuración por entorno.
**Implementado:** `GET /health/live`, configuración validada, pruebas y estructura
modular, conexión PostgreSQL, modelos, migraciones y autenticación propia.
**No implementado:**
sincronización, telemetría, órdenes ni control físico. Los módulos reservados no
exponen rutas. Autenticación se habilita al configurar la conexión exclusiva del rol API. No se requieren credenciales ni servicios externos para arrancar.

## Requisitos y entorno local en Ubuntu

Desde la raíz del repositorio:

```bash
cd backend
python3 --version
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --constraint requirements.lock -e '.[test]'
python -m pip check
```

Se requiere Python 3.12 o posterior. Esta entrega se verificó con Python 3.14.4;
no se afirma haber ejecutado la matriz completa de versiones. Las dependencias
viven en `.venv`, sin cambiar el Python del sistema ni el proyecto Flutter.

Si Ubuntu no incluye `venv`/`ensurepip`, la vía habitual es instalar el paquete
`python3-venv` correspondiente a su Python mediante el administrador del sistema.
En esta computadora se utilizó la alternativa oficial de PyPA, **sin instalar
paquetes globales**, porque `ensurepip` no estaba disponible:

```bash
python3 -m venv --without-pip .venv
curl --fail --location https://bootstrap.pypa.io/get-pip.py --output /tmp/blueflora-get-pip.py
.venv/bin/python /tmp/blueflora-get-pip.py
source .venv/bin/activate
python -m pip install --constraint requirements.lock -e '.[test]'
```

El script se ejecuta con el Python del entorno virtual, nunca con `sudo`.
Referencia: [instalación oficial de pip](https://pip.pypa.io/en/stable/installation/).
Las descargas son dependencias de desarrollo; la aplicación no se integra con
servicios externos.

`pyproject.toml` declara las dependencias directas y `requirements.lock` fija las
versiones resueltas, incluidas las de pruebas. La restricción evita actualizaciones
silenciosas al reproducir esta entrega. El backend editable se instala desde el
código de este repositorio; el aislamiento de compilación puede obtener setuptools.
El archivo lock representa el entorno verificado, no un lock multiplataforma con
hashes. No actualizarlo como parte del arranque normal.

## Configuración

Los valores predeterminados permiten arrancar sin crear `.env`. Opcionalmente:

```bash
cp --no-clobber .env.example .env
```

| Variable | Predeterminado | Valores |
| --- | --- | --- |
| `BLUEFLORA_ENVIRONMENT` | `development` | `development`, `test`, `production` |
| `BLUEFLORA_APP_NAME` | `BlueFlora API` | Texto no vacío |
| `BLUEFLORA_DOCS_ENABLED` | `true` | Booleano; desactiva `/docs` y `/openapi.json` si es falso |

Las variables exportadas tienen prioridad sobre `.env`. El archivo se busca en
la raíz de `backend/`, no en el directorio de trabajo accidental del proceso.
Una configuración inválida impide el arranque con un error de validación.
`ENVIRONMENT` es una etiqueta de configuración, no activa funciones futuras.
Las variables PostgreSQL se documentan en [docs/database.md](docs/database.md).
Son opcionales para arrancar HTTP y obligatorias para migrar/probar PostgreSQL.
No hay claves JWT ni de dispositivos. `.env` y secretos se ignoran en Git.

Ejemplo sin editar archivos:

```bash
BLUEFLORA_ENVIRONMENT=development BLUEFLORA_DOCS_ENABLED=true \
  python -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000 --reload --no-proxy-headers
```

## Iniciar y comprobar

Con el entorno activado, desde `backend/`:

```bash
python -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000 --reload --no-proxy-headers
```

En otra terminal:

```bash
curl --fail http://127.0.0.1:8000/health/live
```

Respuesta HTTP 200:

```json
{"status":"ok"}
```

Documentación local: <http://127.0.0.1:8000/docs>.
Detener con `Ctrl+C`. Se enlaza únicamente a loopback. `--reload` es para
desarrollo; esta fase no proporciona un despliegue público de producción.

Liveness solo confirma que el proceso atiende HTTP: **no confirma PostgreSQL,
autenticación, Raspberry Pi ni entrega de agua**. No se expone `/health/ready`
en esta fase; la conexión se comprueba por separado con `python -m app.db.manage check`.

## Pruebas

```bash
python -m pytest
```

Las pruebas HTTP usan HTTPX con transporte ASGI y el plugin pytest de AnyIO,
sin red externa ni base de datos. No requieren el cliente TestClient de Starlette. Cubren respuesta
HTTP, métodos no permitidos, ausencia de rutas no implementadas, configuración
por entorno/archivo, rechazo de valores inválidos y desactivación de documentación.
Las pruebas HTTP/configuración no leen el `.env` real ni modifican Flutter.
Las nuevas pruebas PostgreSQL leen únicamente su conexión de pruebas y ejecutan
DDL/datos en esquemas aislados dentro de `blueflora_test`. Las pruebas de
autenticación crean y retiran únicamente esquemas efímeros propios para probar
conexiones concurrentes con el rol API real.
Consulta [docs/authentication.md](docs/authentication.md) para roles, endpoints,
políticas, rotación y pruebas de autenticación.
Consulta [docs/database.md](docs/database.md) para configuración, aislamiento,
migración, verificación y reversión.

## Estructura y diseño

- `app/main.py`: fábrica `create_app`; no inicia conexiones al importar.
- `app/core/config.py`: configuración con Pydantic Settings.
- `app/modules/health/router.py`: liveness independiente.
- `app/modules/auth/`: registro, login, tokens opacos, refresh, logout y cuenta autenticada.
- `app/db/`: metadatos, conexión protegida, contexto de propietario y comandos.
- `migrations/`: `0001_initial` y `0002_auth`, con RLS y funciones de permisos mínimos.
- `app/modules/`: auth, gardens, plants, devices, telemetry, irrigation, watering,
  sync; modelos en auth, gardens, plants y watering; los demás quedan reservados.
- `tests/`: configuración y pruebas pytest.
- [docs/architecture.md](docs/architecture.md): esquema relacional preliminar,
  cardinalidades, sitios, grupos hidráulicos, crecimiento y seguridad.

No se crean tablas al arrancar. Las migraciones se aplican explícitamente;
las pruebas PostgreSQL revierten transacciones o retiran sus esquemas efímeros. El documento de arquitectura
distingue las seis tablas implementadas del diseño futuro. La diferencia entre confirmación del controlador y agua físicamente
verificada, y los requisitos de apagado seguro, son condiciones para futuras
entregas: no capacidades que este servidor ya ofrezca.
