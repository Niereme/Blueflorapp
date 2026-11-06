# Autenticación propia — Fase 3.2C

## Roles y perímetro

- `BLUEFLORA_DATABASE_URL`: blueflora_dev sobre blueflora_dev; solo migraciones.
- `BLUEFLORA_TEST_DATABASE_URL`: blueflora_test sobre blueflora_test; prepara pruebas.
- `BLUEFLORA_API_DATABASE_URL`: blueflora_api sobre blueflora_dev; ejecuta HTTP.
- `BLUEFLORA_TEST_API_DATABASE_URL`: blueflora_api_test sobre blueflora_test; pruebas reales de ejecución.

Las cuatro URLs se guardan localmente en `.env`, ignorado por Git, o en variables
de entorno. Las contraseñas se introducen con `\password nombre_rol` en psql,
no como argumentos ni literales SQL. Codificar caracteres especiales en URLs.
No se imprime ni reemplaza el `.env` existente. Los roles API ya fueron creados
por el usuario y no se crean ni alteran administrativamente mediante la migración.
No hay alternativa automática de API a credenciales de migración.

En un despliegue futuro, el proceso API recibirá **solo** sus credenciales, no
las variables de migración. La presencia de API_DATABASE_URL habilita las rutas;
sin ella el servidor conserva liveness independiente, sin fingir autenticación.
El campo environment no selecciona una base implícitamente.

El rol API se valida al abrir transacciones: identidad/base exactas, loopback,
no superusuario, BYPASSRLS, CREATEDB, CREATEROLE, propiedad de tablas ni membresías
adicionales. No posee tablas, no puede asumir el rol de migración ni crear objetos
en public. No recibe privilegios por defecto para objetos futuros.

## Migración 0002_auth

Añade auth_sessions, auth_refresh_tokens y auth_rate_limits, con UUID de sesión,
referencias a users, fechas TIMESTAMPTZ, índices y restricciones. No inserta
usuarios ni datos de demostración. Las tres tablas llevan ENABLE y FORCE RLS;
las cinco tablas personales anteriores conservan ambas opciones. Species sigue
siendo catálogo global y alembic_version metadata privada de migraciones.

Se conceden únicamente:

- SELECT(id,email,is_active,created_at) sobre users al rol API correspondiente.
- EXECUTE sobre siete firmas concretas: auth_register, auth_lookup,
  auth_start_session, auth_access, auth_rotate, auth_logout, auth_attempt.

No hay acceso directo a password_hash, tablas de sesiones ni contadores.
Los permisos específicos sobre recursos se añaden en 0003_resource_permissions
([resources-api.md](resources-api.md)), sin modificar las políticas de autenticación.

Las funciones SECURITY DEFINER pertenecen al rol de migraciones de la base,
distinto del API. Usan `search_path=pg_catalog,pg_temp` y referencias a objetos
cualificadas por esquema, sin SQL dinámico construido desde peticiones. EXECUTE
está revocado de PUBLIC, en la misma transacción de creación, y concedido solo
al rol API de esa base. No hay sobrecargas ni entradas de nombres de objetos.

La búsqueda inicial compara **email = parámetro** y devuelve como máximo una
cuenta al código interno del servidor. No ofrece listado, LIKE, prefijos ni ruta
HTTP de búsqueda. La normalización se hace antes (trim/lower/validación de correo,
sin consultas DNS). Las funciones de registro y sesión no son endpoints SQL
públicos; solo el servidor puede invocarlas con sus credenciales privadas.

Para resolver el acceso previo a una identidad, las funciones activan un contexto
interno temporal. Las políticas internas se aplican EXCLUSIVAMENTE al rol de
migración, nunca al rol API. El valor anterior se guarda/restaura incluso en
retornos tempranos y errores. Se usa set_config dentro de la función porque
PostgreSQL no permite al rol actual declarar ese GUC personalizado en proconfig;
no se solicitan permisos administrativos adicionales. El search_path sí queda
fijado mediante SET en la definición. Las pruebas comprueban la restauración.
Cambiar el indicador desde el rol API no concede acceso privilegiado.

Las consultas de /me obtienen primero usuario/sesión desde el hash de un token
válido y luego establecen owner_id únicamente para esa transacción. El cliente
no elige su propietario: los cuerpos rechazan campos extra y parámetros/cabeceras
de propietario no cambian la identidad. Como siempre, el servidor SQL confía en
el backend: RLS no convierte unas credenciales SQL robadas en acceso seguro.
Los roles de migración pueden cambiar DDL y nunca deben usarse para HTTP.

## Contratos HTTP JSON

| Método y ruta | Entrada | Éxito |
| --- | --- | --- |
| POST /api/v1/auth/register | email, password | 202, mensaje genérico; igual si ya existía |
| POST /api/v1/auth/login | email, password | 200, access_token, refresh_token, token_type, expires_in |
| POST /api/v1/auth/refresh | refresh_token | 200, pareja nueva de tokens |
| POST /api/v1/auth/logout | Authorization: Bearer access_token | 204; revocación idempotente |
| GET /api/v1/me | Authorization: Bearer access_token | id, email, is_active, created_at |

Nunca se devuelve hash, contraseña ni datos de otra cuenta en HTTP. Las respuestas
sensibles incluyen Cache-Control: no-store y Pragma: no-cache. No hay cookies,
correos reales, recuperación de contraseña ni verificación de email. Registrar
un correo no verifica su titularidad; esto se resolverá antes de habilitar flujos
que dependan de esa garantía. La app Flutter no cambia ni utiliza estas rutas aún.

Contraseña de registro: 12–1024 caracteres, sin truncar ni modificar; login admite
1–1024 para devolver un error uniforme de credenciales. Se usa Argon2id explícito
(m=65536 KiB, t=3, p=4), sal aleatoria y comparación de biblioteca. La verificación
de una cuenta inexistente también ejecuta Argon2 contra un hash ficticio. Un
semáforo limita a cuatro cálculos simultáneos por proceso; dimensionar memoria
si se despliegan varios workers. No se requiere clave JWT: los tokens son opacos.

Ambos tokens tienen 256 bits aleatorios y prefijos que separan access/refresh.
Solo se guardan hashes SHA-256, adecuados a secretos aleatorios de alta entropía.
El acceso dura como máximo 15 minutos; la sesión tiene vencimiento absoluto de
30 días desde login, sin extensión al refrescar. expires_in=900 comunica el máximo;
cerca del vencimiento absoluto puede ser menor el tiempo efectivo. Cada refresh
invalida también el access anterior. Toda consulta /me comprueba sesión vigente,
revocación y cuenta activa en PostgreSQL: logout tiene efecto inmediato.

La rotación bloquea la fila de sesión, consume el refresh e inserta el nuevo
hash en una única transacción. Se conserva el hash consumido para detectar replay:
reutilizarlo revoca la sesión completa, incluso los tokens posteriores. Los fallos
de replay confirman esa revocación antes de responder 401. Dos refresh simultáneos
producen como máximo un éxito y la reutilización revoca la sesión; el cliente
futuro debe serializar refresh y no reintentar a ciegas tras una respuesta perdida.
Una interrupción entre COMMIT y recepción de tokens puede requerir otro login.

Errores: 401 authentication_failed para cuenta inexistente, contraseña errónea,
cuenta inactiva o sesión inválida; 422 invalid_request sin reflejar el cuerpo ni
inputs secretos; 429 rate_limited con Retry-After; 503 service_unavailable sin
excepciones SQL, DSN o parámetros. El registro repetido no cambia la contraseña
ni revela existencia por su respuesta. No se promete resistencia perfecta a
análisis estadístico de tiempos o ataques distribuidos.

## Limitación de intentos y operación

Contadores persistentes y atómicos en PostgreSQL, compartidos entre workers:
10 intentos por minuto por IP para registro/login/refresh en conjunto, con
contadores adicionales por operación/IP y correo normalizado en registro/login.
Se limitan intentos exitosos y fallidos por igual; las claves se almacenan como
hashes, no en texto plano (esto no implica anonimización irreversible de correos).
Logout permanece disponible al alcanzar el límite; /me no ejecuta Argon2.

No se confía directamente en X-Forwarded-For. En desarrollo iniciar Uvicorn con
`--no-proxy-headers`; antes de colocar un proxy real configurar explícitamente
qué proxies se consideran confiables y cómo sobrescriben cabeceras. No publicar
HTTP con tokens en texto claro: un despliegue público futuro requiere HTTPS,
secretos separados, límites de tráfico y configuración operativa específica.
La retención/depuración periódica de contadores antiguos y sesiones vencidas
queda pendiente del despliegue; no se borra información previa en esta entrega.

## Comandos y pruebas

Desde backend, entorno virtual activado:

```bash
python -m pip install --constraint requirements.lock -e '.[test]'
python -m app.db.manage upgrade
python -m app.db.manage upgrade --test
python -m app.db.manage current
python -m app.db.manage check-schema
python -m pytest -q -W error
python -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000 --no-proxy-headers
```

Las pruebas anteriores se conservan; la prueba de esquema ahora espera la revisión
0003_resource_permissions. Las nuevas pruebas HTTP usan blueflora_api_test real. Preparan un esquema
UUID nuevo en blueflora_test con el rol de migración y conceden USAGE solo sobre
ese esquema. Para permitir conexiones simultáneas y verificar bloqueo/rotación,
el DDL temporal debe confirmarse. Al terminar se elimina exclusivamente ese
esquema recién creado y sus datos de prueba, nunca public ni información previa.
Las pruebas anteriores mantienen su aislamiento mediante ROLLBACK.

Se prueban dos cuentas, RLS real, campos owner_id falsificados, falta de permisos
para hashes/DDL/SET ROLE, búsquedas exactas, contraseñas erróneas, tokens inválidos,
expiración, rotación concurrente, replay, logout, límites compartidos y su
vencimiento, errores uniformes y ausencia de inputs secretos en respuestas.
No se ejecuta una reversión destructiva sobre desarrollo. La reversión de 0002
solo está habilitada para esquemas temporales de prueba; cualquier reversión
operativa futura requerirá una migración planificada y autorización.

Referencias: [PostgreSQL SECURITY DEFINER](https://www.postgresql.org/docs/current/sql-createfunction.html),
[Argon2-cffi](https://argon2-cffi.readthedocs.io/en/stable/howto.html).
