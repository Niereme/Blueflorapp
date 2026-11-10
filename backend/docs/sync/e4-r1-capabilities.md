> **Cierre autorizado de 3.2E.4 — 2026-11-10.** Hito Git v0.3.5;
> creación de commit y publicación en origin/main autorizadas, publicación pendiente
> de comprobación. Se conservan las limitaciones documentadas. E.5 no iniciada ni
> autorizada. Los estados de preparación anteriores quedan como trazabilidad.

> **Estado vigente al preparar cierre (2026-11-10):** implementación y validación
> técnica E.4 completadas; cierre autorizado, publicación Git pendiente. Suite aislada anterior: 292 aprobadas.
> Respaldo/restauración del origen vacío acreditados y CHECK resuelto por las dos
> variantes exactas; desarrollo migrado a 0005, validado READ ONLY y lifespan/liveness.
> Sin CRUD HTTP en desarrollo ni servicio persistente. E.5 no iniciada ni autorizada.
> Véanse [migración real](e4-development-migration-results.md) y
> [compatibilidad](e4-check-compatibility-results.md).
> El cuerpo conserva la secuencia histórica de propuestas, fallos y resoluciones;
> sus autorizaciones pendientes o estados antiguos no sustituyen este estado vigente.
> Los comandos históricos no son instrucciones para repetir operaciones.

# E.4 — corrección R1 de capacidades

> Actualización autorizada 2026-11-10: ambas variantes exactas del CHECK se
> admiten de forma localizada. La reevaluación offline del ensayo conservado
> dio MATCH y mantiene el fallo inicial como evidencia histórica. Véase
> [compatibilidad y resultados](e4-check-compatibility-results.md). E.4 abierta.

Estado: 2026-11-09. Corrección limitada a la guardia y pruebas aisladas. E.4 abierta;
sin migraciones/conexiones a desarrollo en esta ejecución, despliegue ni publicación Git.
El [preflight anterior](e4-final-review-preflight.md) conserva su evidencia histórica:
la base de desarrollo se observó entonces en 0003; no se ha vuelto a certificar aquí.

## Contrato de capacidades

Una sola fuente normativa: `migrations/versions/0005_capability_manifest.json`.
La proyección está en `0005_capability_query.sql`; 0005 la incorpora y congela el
JSON dentro de `resource_apply(uuid,text)`. Los tres archivos auxiliares se cargan
respecto de `__file__`, nunca del cwd. No se aprende el contrato del destino al
migrar/arrancar. El artefacto explícito fue construido y revisado contra el DDL
0001–0005 en una fixture limpia de blueflora_test, no contra desarrollo.
Las migraciones 0001–0003 no se modificaron. 0005 sigue sin aplicarse en desarrollo.

Se comparan objetos JSONB completos, sin buscar subcadenas ni confiar en nombres
de constraints/políticas. Los OID se resuelven a columnas ordenadas, tipos, roles
y relaciones dentro del esquema; M/R representan los dos roles existentes.
Contrato soportado: PostgreSQL **18** (ejecución real 18.6). Expresiones CHECK,
defaults, USING/WITH CHECK y WHEN usan exactamente `pg_get_expr(...,false)` bajo
`search_path=pg_catalog,pg_temp`; otra representación no se acepta por aparente
equivalencia. Un cambio de versión mayor requiere revisar el contrato y probarlo.

Capacidades comprobadas:

- Las 14 tablas conocidas: dueño, clase, columnas completas, tipos/typmods,
  nulabilidad, defaults, identidad/generación y ENABLE/FORCE RLS.
- PK, UNIQUE, CHECK, NOT NULL y FK: columnas ordenadas, tabla/columnas referidas
  del mismo esquema, acciones, match, diferibilidad, validación/enforcement y
  propiedades de validez/unicidad/readiness del índice asociado. Incluye las FK
  compuestas de owner/identidades/historial y grupo/recibo diferidas.
- Todas las políticas de esas tablas: cantidad, comando, permisividad, roles
  aplicables y expresiones exactas USING/WITH CHECK, incluidas las excepciones
  auth_internal ya existentes de 0002.
- ACL de tablas/columnas, PUBLIC y otros grantees, además de privilegios efectivos
  de R por tabla/columna y grant options. Sin DML de recursos ni SELECT de tablas
  privadas/alembic_version; solo las cuatro columnas públicas de users.
- Las nueve funciones conocidas: firma/argumentos/retorno, lenguaje, dueño,
  SECURITY DEFINER/INVOKER, search_path/configuración completos, strictness,
  defaults, volatilidad, ACL/PUBLIC y EXECUTE efectivo/grant option de R.
- Triggers no internos de esas tablas: eventos/momento/nivel, habilitación,
  función del mismo esquema, argumentos, columnas, WHEN y diferibilidad.
  `reject_immutable()` además exige el cuerpo exacto aprobado y SECURITY INVOKER.
- Atributos/membresías de M/R, propietario admisible del esquema, USAGE sin CREATE
  de R, ausencia de CREATE de PUBLIC/escritura de esquema/base por R, y disponibilidad
  ejecutable de sha256/gen_random_uuid incorporados.

El bootstrap Python verifica la firma y seguridad del gateway antes de invocarlo;
no duplica el manifiesto de tablas/políticas/relaciones. La consulta privilegiada
lee catálogos y el head, pero devuelve únicamente
`{"ready":true,"manifest":"e4-r1-pg18"}` o un error genérico. No concede SELECT
sobre ledger/alembic_version, ni crea funciones/roles/grants nuevos.

Límites: es un contrato de capacidades esenciales, no una prueba de equivalencia
SQL arbitraria ni un hash de todo el esquema/código. No atestigua cuerpos de auth
ni del propio gateway contra un administrador que pueda reemplazarlos; conserva
la confianza aprobada en M y en el proceso/conexión API. Objetos ajenos a las
14 tablas y nueve nombres de función requieren revisión del diff/preflight;
no quedan certificados automáticamente. La guardia no audita datos ni repara nada.
Un error que impida verificar readiness bloquea recursos/arranque; liveness
continúa representando proceso vivo. No se cambió la frontera autenticada del GUC.

## NULL, contexto y ausencia de DML

La rama técnica se ejecuta antes de interpretar owner_id. No contiene DML,
set_config, generación de UUID ni creación perezosa de owner_state. Los parámetros
NULL parciales se rechazan explícitamente con SQLSTATE 22023. Una mutación con
ambos argumentos presentes sigue exigiendo owner y autenticación HTTP previa;
una consulta técnica exitosa no establece identidad ni autoriza una mutación.

Pruebas reales: READ ONLY con COMMIT, owner ausente/vacío/UUID e incluso texto
inválido (no se interpreta en la rama técnica), propietario real autenticado,
contexto exacto antes/después (owner/auth_internal/search_path/TimeZone/read_only/
current_user), recuentos de todas las tablas visibles de la fixture conservados,
y cero state/operaciones/grupos nuevos. Ambas variantes parciales se rechazan
con/sin owner y sin efectos. HTTP sin credenciales devuelve 401 después del probe;
la llamada SQL de mutación sin owner devuelve 42501. No se promete autenticar al
portador de credenciales SQL runtime comprometidas: ese límite sigue vigente.

## Desviaciones sintéticas y regresiones

18 desviaciones independientes, siempre conservando head 0005: USING, WITH CHECK,
rol y comando de política; FORCE y ENABLE; UNIQUE y FK compuesta; permiso de
columna R/PUBLIC; SELECT privado efectivo; INSERT PUBLIC; trigger deshabilitado;
cuerpo de su función; SECURITY DEFINER y search_path del gateway; tipo y nulabilidad.
Cada fixture correcta se acepta primero; después la guardia y el lifespan
rechazan la desviación, mientras /health/live sigue respondiendo 200.
No se alteraron roles globales ni objetos de public para fabricar los casos.

Se conserva la cobertura anterior de rollback en datos/grupo/recibo. Como sus
triggers extra de inyección violan deliberadamente el manifiesto, esas tres pruebas
atestiguan primero el esquema correcto y omiten únicamente esa guardia durante
la petición con fallo sintético. Autenticación/gateway/transacción permanecen
reales y se exige observar SQLSTATE 23514; así no se confunde rechazo de readiness
con rollback del gateway. No existe bypass de producción.
La copia limpia de migraciones incluye SQL/consulta/JSON y migra desde otro cwd;
acepta el manifiesto instalado sin depender de archivos externos.

## Ejecuciones de validación

Desde `backend/`, usando el Python existente `.venv/bin/python`:

```bash
.venv/bin/python -m pytest tests/test_capabilities.py tests/test_mutations.py::test_failure_at_each_stage_rolls_back_everything -q -W error --tb=short
# 31 passed in 18.60s (28 nuevas + 3 regresiones de atomicidad).
.venv/bin/python -m pytest -q -W error --tb=short
# 248 passed in 172.65s; 220 anteriores + 28 nuevas.
.venv/bin/python -m pip check
# No broken requirements found.
git diff --check
# Sin errores.
```

Una ejecución focalizada previa ya había aprobado las 28 nuevas en 13.78s;
la ejecución final de 31 añadió la confirmación de los tres fallos inyectados.
La suite completa se ejecutó una sola vez tras esa validación. Todas las pruebas
PostgreSQL usaron exclusivamente fixtures/esquemas efímeros de blueflora_test.

Las 220 pruebas anteriores corresponden a implementación E.4, las 158 a 3.2D y
las 319 Flutter/validación Android a E.3. No se ejecutó Flutter ni se operó el teléfono.
Las primeras ejecuciones focalizadas detectaron aliases ambiguos PL/pgSQL y un
error del harness al dividir un cuerpo SQL; se corrigieron antes del resultado
final. No se modificaron dependencias ni versiones.

## Respaldo/restauración: únicamente preparación

Consulta nueva de solo lectura a pg_roles desde **blueflora_test**, verificando
primero destino/rol: existe `postgres` con LOGIN/SUPERUSER/BYPASSRLS/CREATEDB.
Por sus atributos es candidato técnico para pg_dump completo pese a FORCE RLS.
Esto no acredita credenciales disponibles, permiso de conexión a desarrollo,
pg_hba ni autorización para usarlo. No se conectó con ese rol ni se intentó obtener
credenciales. M/R siguen sin BYPASSRLS/CREATEDB; no son sustitutos de esa identidad.
No hay respaldo recuperable acreditado ni prueba de restauración nueva.

Antes del corte, un operador autorizado deberá usar una identidad existente
aprobada para crear el pg_dump coherente completo descrito en el preflight, con
escritores drenados, destino privado, owners/ACL incluidos, salida/error verificados
y hash. No --enable-row-security, --no-owner o --no-acl para simular integridad.
No otorgar BYPASSRLS al migrador ni alterar roles/membresías/credenciales reales.

**Este plan sustituye el ejemplo de restauración en 127.0.0.1 del informe anterior:**
el ensayo debe usar una instancia PostgreSQL 18 aislada, sin aplicaciones/clientes,
sin conectividad hacia las bases reales, sin credenciales reales y con almacenamiento
separado. No ejecutar SQL/código del archivo en el clúster de desarrollo/pruebas.
El destino no puede ser blueflora_dev ni blueflora_test, ni sobrescribir una base.
Debe disponer previamente de las identidades con nombres/atributos necesarios
para conservar owners y ACL; no ejecutar CREATE/ALTER ROLE ni GRANT de membresías
como parte de la restauración. Su existencia/disponibilidad todavía no está probada.

Procedimiento futuro, sujeto a verificar aislamiento y aprobar operador/destino:

1. Inventariar el archivo con pg_restore --list, sin publicar contenido; verificar
   hash y versión. Revisar offline cualquier contenido ejecutable antes de restaurar.
2. Con un servicio libpq de destino aprobado (sin secretos versionados), comprobar
   identidad de instancia, base nueva vacía y roles existentes. Un puerto distinto
   por sí solo no demuestra aislamiento. No usar conexiones Settings de la app.
3. Restaurar solo allí: `pg_restore --exit-on-error --single-transaction
   --dbname="service=blueflora_e4_restore_isolated" "$BF_E4_BACKUP_FILE"`.
   El servicio debe apuntar a la base nueva aprobada y separada, nunca a las reales.
   No ejecutar contenido restaurado ni conectar la aplicación fuera de esa instancia.
4. En READ ONLY contrastar head, tablas/columnas/constraints/índices, owners,
   atributos/membresías de roles, ACL efectivos/PUBLIC, políticas FORCE y funciones;
   comparar recuentos y resúmenes criptográficos privados del origen/copia, sin
   publicar datos ni secretos. Lecturas completas requieren el operador competente;
   no desactivar RLS ni confundir filas ocultas con ausencia de datos.
5. Antes de considerar recuperable la copia, revisar funciones restauradas y ejecutar
   cualquier prueba de recuperación funcional exclusivamente dentro del destino
   aislado y bajo autorización específica. Listado/hash/recuentos solos no certifican
   toda recuperación funcional. Registrar resultados agregados y limpiar el entorno
   únicamente con autorización; no limpiar bases existentes.

Con las conexiones actualmente disponibles no puede acreditarse ese ensayo ni
crearse un respaldo completo. Acción administrativa mínima pendiente: autorizar a
un operador con identidad existente capaz (candidato postgres), y proporcionar un
destino aislado preparado con las identidades necesarias. Si no existe tal destino,
su aprovisionamiento y cualquier necesidad de identidades allí requieren decisión
separada; no se amplían privilegios en el clúster real. No se crearon dumps, bases,
instancias ni restauraciones durante R1.

## Próximo paso

Revisar este diff y los resultados R1; resolver y acreditar respaldo/restauración
antes de solicitar el corte conjunto de desarrollo. Parada de escritores, nuevo
preflight, migración, delta ACL, despliegue/arranque, escrituras de humo y publicación
Git siguen requiriendo autorización. No se declara cerrada E.4 ni se inicia otra fase.

## Archivos de esta corrección y Git

Respecto del estado recibido, R1 afecta exclusivamente:

- app/modules/common/repository.py
- migrations/versions/0005_mutation_gateway.py
- migrations/versions/0005_mutation_gateway.sql
- migrations/versions/0005_capability_query.sql (nuevo)
- migrations/versions/0005_capability_manifest.json (nuevo)
- tests/test_capabilities.py (nuevo)
- tests/test_mutations.py
- docs/sync/e4-r1-capabilities.md (nuevo)
- docs/sync/e4-deployment.md
- docs/sync/e4-final-review-preflight.md (nota que enlaza la corrección)
- docs/sync/e4-validation-results.md (adenda de resultados)

main permanece en af2bd84dadae3fba8a8fd8119c54a2307520cfa9; índice vacío.
Se conservan los cambios E.4 anteriores y .vscode/ fuera del índice. No se
prepararon archivos ni se hicieron commits/push. Sin cambios de dependencias,
roles globales, permisos reales o migraciones aplicadas en desarrollo.
