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

# E.4 — compatibilidad exacta del CHECK y reevaluación offline

Estado: 2026-11-10. Dos correcciones autorizadas y separadas: comparador offline
del ensayo y guardia R1. **E.4 abierta; desarrollo sin migrar.**

## Regla única, explícita y localizada

Fuente: migrations/versions/0005_diameter_check_contract.json, versión
`bf-growth-diameter-exact-v1`. Contiene los dos textos completos comprobados en
[e4-check-restore-diagnostic.md](e4-check-restore-diagnostic.md), sin regex,
subcadenas, eliminación de casts ni equivalencia SQL arbitraria.

La regla solo corresponde a growth_history / ck_growth_history_diameter_kind,
CHECK con columnas ordenadas diameter_m y diameter_kind. Tipos double precision y
varchar(20), nullable, sin defaults/identity/generated. Collation: diámetro sin
collation; clase pg_catalog.default. Validado/enforced, local, sin herencia,
NO INHERIT=false, sin diferibilidad. Los otros campos de la constraint deben
coincidir exactamente con el contrato. Solo esos dos textos se convierten a la
forma original antes de ordenar/comparar constraints; ninguna entrada se elimina.
CHECK ausente/duplicado/TRUE/NULL, guardas debilitadas, valores adicionales,
expresiones terceras, tipos/columnas/collation/propiedades distintas se rechazan.

### Comparador del ensayo

Nuevo app/db/restore_comparison.py, versión `bf-restore-inventory-v2`. No conecta
a PostgreSQL ni ejecuta SQL; trabaja con copias profundas y deja intactos inputs.
Verifica el contrato incluso si ambos snapshots comparten una misma desviación
inválida de este CHECK. Mantiene comparación exacta del resto del inventario y
solo normaliza además el LOGIN true→false ya documentado de M/R.

Los inventarios antiguos omitían collation/nombre de constraint. Para estos,
exige evidencia DDL guardada: un único CREATE TABLE public.growth_history con
las dos líneas de columna exactas sin COLLATE y el CHECK nombrado exacto, más
igualdad de la configuración de base (encoding/locale/collation). Registra hash
y método `saved-pg_dump-DDL-default-column-collation`. Se deriva el default del
DDL del dump y del mismo SQL aplicado en el ensayo; **no** se afirma haber leído
attcollation histórico de catálogos que nunca lo almacenaron. Sin esa evidencia,
con collation explícita distinta o DDL no reconocido, se rechaza. Los snapshots
modernos registran collation por columna y la capacidad técnica confirmada.
No se usa una equivalencia de texto aislada para suplir metadatos incompatibles.

### Guardia R1 y delta exacto de 0005 no aplicada

- Nuevo 0005_diameter_check_contract.json: contrato compartido, no una tabla nueva.
- 0005_capability_query.sql: CTE con lista cerrada; verifica nombre, tabla,
  conkey/tipos/typmods, collation, nulabilidad/defaults y propiedades. Canonicaliza
  solo una constraint aprobada antes de agregar/ordenar. Añade la capacidad
  diameter_check_contract y collation de las dos columnas al JSON técnico.
- 0005_capability_manifest.json: conserva todas las expresiones anteriores,
  incluyendo el CHECK original. Solo añade collation a esas dos columnas y exige
  diameter_check_contract=true. Las otras capacidades permanecen exactas.
- 0005_mutation_gateway.py: carga el JSON auxiliar junto a __file__ e inserta la
  regla congelada en la proyección SQL; el test de copia limpia incluye el nuevo
  auxiliar. Sin funciones/grants/roles/DDL adicionales ni DML en el probe.

El bootstrap Python y la respuesta técnica e4-r1-pg18 se conservan; no se cambian
los ocho escritores, la firma pública ni la frontera de confianza del GUC.
0001–0003, 0004, el cuerpo de mutaciones 0005.sql, dependencias y la restricción
real de desarrollo no se modificaron por esta corrección.

## Verificaciones de código

Ejecuciones reales de esta corrección, desde backend/:

- `.venv/bin/python -m pytest tests/test_check_restore_compatibility.py tests/test_check_restore_diagnostic.py tests/test_capabilities.py -q -W error --tb=short`: **72 aprobadas en 22.93 s**.
- `.venv/bin/python -m pytest -q -W error --tb=short`: **292 aprobadas en 178.88 s**, sin fallos.
- `.venv/bin/python -m pip check`: No broken requirements found.
- `git diff --check`: correcto. Sin actualizaciones de dependencias.

Los resultados 220/248 son ejecuciones anteriores, no el recuento actual.

Las 248 pruebas R1 y nueve del diagnóstico son antecedentes. Se conservó la
matriz de 106 casos sintéticos × tres definiciones y el mini roundtrip de test;
no se repitió la restauración real conservada. La prueba histórica que esperaba
rechazo de la variante reconstruida ahora exige aceptación bajo la autorización
actual; las de CHECK ausente/TRUE/NULL siguen negativas. Se añadieron 35 pruebas
positivas/negativas offline y R1 (tipos, collation, not-null, NOT VALID, NO INHERIT,
nombre, columnas, duplicados, valores extra, otros ACL/CHECK y metadatos booleanos).
También se ejecutaron las 28 pruebas de capacidades anteriores, incluidas sus
18 desviaciones, NULL/contexto/no DML y carga desde copia limpia.

## Reevaluación real: MATCH sin diferencias pendientes

Se reevaluó **la restauración ya ejecutada**, no una nueva restauración.
Resultado nuevo privado, creado con O_EXCL/0600:

`/home/niereme/.local/share/blueflora/restore-e4/run-DJMNne0r/evidence/reevaluation-bf-restore-inventory-v2.json`

SHA-256 del resultado:
`ba7f6281327b67f5a288dd32a7b95b8751503d57ddf6acbb9bef54e43ca2a3e9`.
Versión de comparador/regla y sus hashes están guardados, junto a hashes de
inventarios, DDL, ejecución, sesión, fallo inicial y dump. Manifiesto separado
reevaluation-bf-restore-inventory-v2.sha256 verificado. No se sobrescribió el
resultado inicial FAILED ni su manifest evidence-files.sha256.

Después de la regla autorizada y LOGIN→NOLOGIN, **no quedan otras diferencias**.
Se conservan los registros de aplicación SQL código 0, aserciones sin roles LOGIN
ni contraseñas y stderr vacío. Sin WARNING/ERROR/FATAL/PANIC detectados en los logs.
La parada se volvió a comprobar offline: pg_controldata salida 0, estado shut down
y data/postmaster.pid ausente. No se arrancó el clúster ni se reactivó LOGIN.

Respaldo original: 98161 bytes, SHA-256
`c2ba46963b76ab97bedcff73ba70272d468d4640c1a39c27f1a5bee2f24961be`.
SHA256SUMS original y evidence-files.sha256 siguen correctos; todos los inputs
verificados antes y después de la reevaluación conservan sus hashes. No se alteró
el backup, inventarios, SQL, logs ni PGDATA. Solo se añadieron los dos resultados
nuevos de reevaluación y su checksum privado.

Con estas condiciones, el ensayo conservado es **satisfactorio para las
comprobaciones de esquema/permisos y origen vacío realizadas**, bajo la regla
exacta autorizada. No es recuperación de datos poblados, prueba de rendimiento,
autenticación funcional, PITR ni garantía sobre escrituras posteriores al dump.
El fallo inicial sigue siendo un hecho histórico y no se borra.

## Archivos de esta entrega

Código/auxiliares: app/db/restore_comparison.py;
migrations/versions/0005_diameter_check_contract.json, 0005_capability_query.sql,
0005_capability_manifest.json y 0005_mutation_gateway.py.
Pruebas: tests/test_check_restore_compatibility.py (nuevo),
tests/test_check_restore_diagnostic.py (expectativa de aceptación actualizada).
Documentación: este informe, procedimiento y notas en resultados de restauración,
diagnóstico, R1, validación y despliegue. La captura B histórica y su script
congelado no se reescriben: para futuras capturas se debe regenerar el script
contra el procedimiento actualizado, que ahora inserta el contrato JSON auxiliar.
No reutilizar el script B antiguo contra una proyección SQL nueva.

## Git, límites y siguiente paso

main permanece en af2bd84dadae3fba8a8fd8119c54a2307520cfa9, índice vacío. Cambios
anteriores y .vscode/ conservados; sin commits/push ni tags. No se migró desarrollo,
se desplegó, instaló nada ni se operó el teléfono. E.4 sigue abierta.

Revisar el diff de esta compatibilidad y sus pruebas. La reevaluación resuelve la
puerta de este ensayo específico; antes de migrar todavía hay que autorizar una
ventana real, revalidar origen/datos/ACL/disco y vigencia del respaldo y concretar
el corte conjunto 0004/0005. No inferir esa autorización del MATCH ni cerrar E.4.
