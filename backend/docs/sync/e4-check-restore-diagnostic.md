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

# E.4 — diagnóstico focalizado del CHECK restaurado

> Actualización autorizada 2026-11-10: ambas variantes exactas del CHECK se
> admiten de forma localizada. La reevaluación offline del ensayo conservado
> dio MATCH y mantiene el fallo inicial como evidencia histórica. Véase
> [compatibilidad y resultados](e4-check-compatibility-results.md). E.4 abierta.

Fecha: 2026-11-10, America/Mexico_City. Diagnóstico y pruebas autorizados; **sin
modificar producción, comparador, manifiesto R1 o migraciones**. E.4 permanece
abierta. El ensayo completo anterior no se repitió ni se aprobó retroactivamente.

## Evidencia exacta conservada

Restricción: **ck_growth_history_diameter_kind**, tabla public.growth_history.
Nombre conservado en el DDL emitido por pg_restore; expresión original tomada
del inventario source-after.json, restaurada de restore.inventory.json. Esos
inventarios guardan pg_get_expr, no pg_get_constraintdef ni nombres de constraints;
no se atribuye a ellos información que no contienen. El DDL y 0001 corroboran
nombre y expresión; no se hizo una nueva consulta a desarrollo.

Original almacenada, pg_get_expr(conbin,conrelid,false):

```sql
(((diameter_m IS NULL) AND (diameter_kind IS NULL)) OR ((diameter_m IS NOT NULL) AND (diameter_kind IS NOT NULL) AND ((diameter_kind)::text = ANY ((ARRAY['stem'::character varying, 'canopy'::character varying])::text[]))))
```

Restaurada almacenada, misma llamada de deparse:

```sql
(((diameter_m IS NULL) AND (diameter_kind IS NULL)) OR ((diameter_m IS NOT NULL) AND (diameter_kind IS NOT NULL) AND ((diameter_kind)::text = ANY (ARRAY[('stem'::character varying)::text, ('canopy'::character varying)::text]))))
```

Fragmento exacto del CREATE TABLE conservado en restore.sql (la coma corresponde
al separador de constraints del CREATE TABLE):

```sql
CONSTRAINT ck_growth_history_diameter_kind CHECK ((((diameter_m IS NULL) AND (diameter_kind IS NULL)) OR ((diameter_m IS NOT NULL) AND (diameter_kind IS NOT NULL) AND ((diameter_kind)::text = ANY ((ARRAY['stem'::character varying, 'canopy'::character varying])::text[]))))),
```

La migración 0001 original expresa la condición mediante IN ('stem','canopy').
No se cambió ese archivo. Columnas: diameter_m DOUBLE PRECISION nullable y
diameter_kind VARCHAR(20) nullable, ambas sin default. Las otras restricciones
relevantes siguen exigiendo diámetro positivo y menor que Infinity, si existe,
y al menos altura o diámetro. No se confunde el CHECK de clase con el de rango.

Versiones: servidor origen y pg_dump 18.6, paquete Ubuntu
18.6-0ubuntu0.26.04.1, archive format 1.16-0; pg_restore y servidor aislado 18.6.
El ciclo sintético también utilizó binarios /usr/lib/postgresql/18/bin y servidor
18.6. Deparse normalizado: search_path=pg_catalog,pg_temp; TimeZone=UTC;
pg_get_expr(...,false) y pg_get_constraintdef(...,false) en las pruebas.
Base/locale de la evidencia: UTF8, libc, en_US.UTF-8, collation version 2.43.

## Causa comprobada y árbol resuelto

La diferencia **no aparece en el SQL emitido**: el archivo conservado contiene
la forma original, no la restaurada. Se reprodujeron dos caminos sintéticos:

1. Definir con IN, leer pg_get_constraintdef y volver a parsear ese DDL en la misma
   tabla de prueba: cambia a la forma restaurada. Una siguiente relectura/reparse
   conserva ya la nueva representación.
2. pg_dump --schema-only --format=custom del esquema sintético, pg_restore a SQL
   y psql en otro esquema UUID de **la misma blueflora_test**: el SQL todavía
   contiene la forma original; el catálogo tras aplicarlo contiene la restaurada.

No es solo formato de pg_get_expr: conbin cambia de un **ArrayCoerceExpr**
(coerción del array varchar[] a text[]) a un **ArrayExpr** cuyos elementos están
relabelados a text. El IN inicial construye la primera forma; el parse de su
representación con cast explícito del array construye la segunda. Se comprobó
el cambio de árbol antes de reconstruir el texto del catálogo. No se atribuye
corrupción al dump ni un cambio de valor por pg_restore. No se investigó el código
interno exacto del parser C ni se generaliza a otras versiones PostgreSQL.

Tipos/operadores comprobados en catálogos y expresiones:

- Lado izquierdo: diameter_kind varchar(20), convertido a text.
- Ambas formas de array resuelven a text[]; constantes stem/canopy mantienen sus
  valores y orden, sin elementos NULL, cambio de case, trim o normalización.
- Operador resuelto **=(text,text)**, resultado boolean, función texteq(text,text),
  estricta. Iguales inputcollid y useOr=true en ScalarArrayOpExpr.
- Cast varchar→text: pg_cast.castmethod='b', castcontext='i', castfunc=0:
  conversión binaria/implícita sin función transformadora. Mover ese cast entre
  array y sus elementos no cambia esos valores. Los guardas IS NULL/IS NOT NULL
  de las dos expresiones son iguales.

La evidencia estructural y la matriz demuestran equivalencia de estas **dos
variantes exactas en el dominio comprobado**; no basta la presencia de las palabras
stem/canopy. No es un algoritmo para probar equivalencia SQL arbitraria.

## Pruebas realmente ejecutadas

Archivo nuevo: tests/test_check_restore_diagnostic.py. Conexión M de test existente,
verify_database antes de DDL, esquemas bf_test_UUID exclusivos y limpieza de esos
esquemas solamente. Sin roles globales, sudo, instalaciones, cambios de permisos
reales ni nueva instancia. Se usó la fixture auth_db existente solo para probar
la guardia R1 en esquemas efímeros. No se conectó al origen de desarrollo ni se
arrancó el clúster de restauración conservado.

```bash
cd /home/niereme/Documents/Blueflorapp/backend
.venv/bin/python -m pytest tests/test_check_restore_diagnostic.py -q -s -W error --tb=short
# Resultado final: 9 passed in 3.38s
```

- Matriz: 106 casos sintéticos × 3 definiciones = 318 intentos de CHECK, comparando
  expresión original inventariada, expresión restaurada y definición inicial IN.
  Incluye NULL en cada campo, stem/canopy, inválidos, vacío, mayúsculas, espacios,
  tab/nueva línea; diámetros NULL, negativos, -0, mínimo subnormal positivo,
  positivo normal, ±Infinity y NaN; altura presente/ausente para has_measurement.
- El CHECK completo de clase produce TRUE/FALSE, nunca UNKNOWN en esa matriz.
  La subexpresión de membresía sí produce TRUE/FALSE/NULL: NULL si kind es NULL.
  Una tabla control confirma que un CHECK de membresía solo acepta UNKNOWN;
  ese debilitamiento no equivale al CHECK completo con guardas.
- La aceptación/rechazo efectivo coincide entre las tres tablas. El CHECK de
  clase por sí solo no valida el rango: NaN/Infinity/cero/negativos con kind válido
  se rechazan por el CHECK finito/positivo compartido, no por pertenencia.
- Longitud >20 con caracteres no espaciales: 22001; exceso compuesto solo por
  espacios puede recortarse al asignar varchar(20), pero los espacios restantes
  hacen fallar el CHECK (23514). No se atribuye trim al comparador ni al dominio.
- Tipos, operadores, cast binario/collation, reparse estable y roundtrip schema-only
  real comprobados. Los archivos del mini ciclo son exclusivamente sintéticos,
  en directorios pytest temporales, sin tocar los respaldos originales.

La primera ejecución focalizada obtuvo 5 passed/1 failed por esperar 22001 también
para un exceso de espacios: PostgreSQL permite ese recorte en varchar. Se corrigió
la expectativa de la prueba y se añadieron casos R1 de debilitamiento antes del
resultado final. No se corrigió código de producción. No se repitió la suite completa.

## Impacto directo sobre R1

El manifiesto explícito contiene la forma original de este CHECK, en
0005_capability_manifest.json, tablas.growth_history.constraints; la consulta
0005_capability_query.sql obtiene la expresión exacta mediante pg_get_expr.
0004 no redefine este CHECK. No se modificó ninguno de esos archivos.

Prueba directa en auth_db: esquema E.4 correcto aceptado por R1; solo se elimina
/recrea esta restricción con su propio pg_get_constraintdef, manteniendo tipos,
convalidated/conenforced, diferibilidad y head 0005. **R1 lo rechaza** con
DatabaseConfigurationError. La misma variación puede, por tanto, bloquear una
restauración válida respecto de este CHECK; no queda limitada al comparador del
ensayo. No se declara probado el dump/restauración de todo E.4 ni se aplicó 0005
al clúster conservado para demostrarlo.

Pruebas adicionales independientes: R1 también rechaza el CHECK ausente,
CHECK(TRUE) y CHECK(NULL::boolean). Estos dos últimos aceptarían datos inválidos;
no se deben admitir como si fueran variantes textuales equivalentes.

## Corrección mínima propuesta, todavía no aplicada

Separar las dos autorizaciones:

1. **Comparador del ensayo:** aceptar solo las dos expresiones completas copiadas
   arriba para esta restricción de growth_history, localizando además tipo CHECK,
   columnas y tipos esperados y propiedades de validación/enforcement/diferibilidad.
   Convertir únicamente esa pareja exacta a una representación fija antes de
   comparar y ordenar; el resto del inventario debe permanecer idéntico. No ignorar
   otras constraints, entradas ausentes/duplicadas, nombres/tipos o relaciones.
   No eliminar casts por regex ni buscar subcadenas stem/canopy.
2. **Guardia R1:** decisión separada para añadir una canonicalización igualmente
   cerrada a la proyección SQL de ese CHECK (antes de ordenar el array de
   constraints), conservando el manifiesto original como referencia si es viable.
   No permitir simplemente que falle el catálogo ni devolver ready constante.
   Mantener ENABLE/FORCE, políticas, ACL/columnas y todas las otras capacidades.

Cualquier expresión tercera, CHECK ausente, TRUE/NULL, operador/array/tipo/columna
incorrectos o propiedades distintas seguirá causando rechazo. Antes de aprobar
esa implementación se deben añadir pruebas de ambas variantes aceptadas y de
mutaciones debilitadas rechazadas en cada capa, conservando los negativos nuevos.
No es necesario reescribir datos, tocar la restricción de desarrollo ni cambiar
0001–0003 para resolver este falso negativo de representación.

Autorización necesaria: editar/probar el comparador del ensayo por un lado, y la
proyección/guardia R1 con sus pruebas aisladas por otro; cualquier ajuste de 0005
no aplicada debe quedar explícito. Revisión de diff y verificaciones pertinentes
antes de autorizar otro ensayo completo en un destino nuevo. No se relajan ambas
capas automáticamente. Migrar desarrollo, arrancar/reparar el destino conservado,
publicar Git o cerrar E.4 requieren otras autorizaciones y no se recomiendan aquí.

## Conservación y Git

Solo se añadieron esta documentación y la prueba focalizada; se enlazó el diagnóstico
desde el resultado previo. Producción, comparador, manifiestos, migraciones,
dependencias y bases de desarrollo/restauración conservada permanecen intactos.
Dump SHA-256 verificado: c2ba46963b76ab97bedcff73ba70272d468d4640c1a39c27f1a5bee2f24961be;
SHA256SUMS original y evidence-files.sha256 del ensayo correctos. El clúster sigue
sin postmaster.pid; no se inició ni reactivó LOGIN. No se alteró evidencia anterior.

main sigue en af2bd84dadae3fba8a8fd8119c54a2307520cfa9; índice vacío y cambios
anteriores conservados, incluida .vscode/. git diff --check correcto. Sin
commit/push, migración, despliegue o inicio de fase posterior. E.4 abierta.
