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

> Estado vigente 2026-11-10: migración conjunta 0004+0005 de blueflora_dev.public
> ejecutada y comprobada mediante lecturas; head 0005_mutation_gateway, recuentos
> conservados y R1 aceptada. Readiness temporal correcta y proceso cerrado.
> Véase [resultado de migración](e4-development-migration-results.md). Sin despliegue persistente ni cierre de E.4.
> Las secciones anteriores/planes históricos se conservan como antecedentes.

# E.4 — preflight y corte de desarrollo pendientes

> Actualización autorizada 2026-11-10: ambas variantes exactas del CHECK se
> admiten de forma localizada. La reevaluación offline del ensayo conservado
> dio MATCH y mantiene el fallo inicial como evidencia histórica. Véase
> [compatibilidad y resultados](e4-check-compatibility-results.md). E.4 abierta.

> Ensayo autorizado posterior: bwrap y aplicación SQL terminaron, pero la
> comparación estricta falló en una expresión CHECK. Instancia privada
> detenida y respaldo íntegro; no se acredita éxito completo. Véase
> [resultado real del ensayo](e4-restore-validation-results.md).

> Intento autorizado posterior (2026-11-09): **bloqueado antes de captura**
> porque sudo -n exigió autenticación interactiva. No se generó dump ni se
> ejecutó bwrap/restauración. Véanse [resultados reales](e4-backup-restore-results.md).
> El procedimiento siguiente se conserva; no es evidencia de ejecución exitosa.

Actualización R1 2026-11-09: la corrección de capacidades y sus pruebas aisladas
se documentan en [e4-r1-capabilities.md](e4-r1-capabilities.md). El plan de
restauración de ese informe sustituye el ejemplo anterior en el clúster real:
requiere una instancia aislada preparada y autorización posterior. No se creó
respaldo ni destino de restauración. Desarrollo sigue sin modificaciones.

Antecedente de revisión 2026-11-09: se completó exclusivamente el
[preflight READ ONLY y la revisión final](e4-final-review-preflight.md).
Desarrollo sigue en 0003 y sin datos de recursos/usuarios. Se recomienda corregir
la guardia/probe y acreditar respaldo recuperable antes del corte; ver hallazgo R1
y comandos propuestos en ese informe. No se migró ni desplegó.

Este procedimiento de corte **no se ejecutó** en desarrollo. La autorización actual solo
permite código, dependencia aprobada y esquemas temporales de blueflora_test.
No detener/desplegar servicios, migrar public ni cambiar atributos de roles.

## Preparación ejecutable pendiente de autorización

El [procedimiento de respaldo y restauración](e4-backup-restore-procedure.md)
concreta herramientas 18.6, acceso OS postgres sin contraseña y una instancia
privada de niereme con bwrap, roles equivalentes NOLOGIN y comparación técnica.
Sustituye los ejemplos anteriores de restore. No se ejecutaron comandos de
respaldo/instancia/roles: la disponibilidad efectiva del sandbox y el acceso
administrativo aún no están acreditados. La restauración propuesta genera SQL
antes de NOLOGIN y lo aplica/verifica en una única sesión psql, sin reconexiones.
La revisión estática posterior corrigió el formato JSON y evitó prompts de sudo;
no equivale a una ejecución real. Las 248 pruebas son evidencia anterior.

## Revisión previa a solicitar autorización

- Revisar diff, alcance, suite y firma/delta ACL de 0004/0005. Mantener 0001–0003.
- Confirmar una ventana de mantenimiento y quién opera el servicio y los respaldos.
- Confirmar respaldo PostgreSQL coherente con WAL y verificación de recuperación;
  no incluir dumps, credenciales ni datos en Git o informes.

## Preflight de desarrollo a autorizar por separado

Con rol migrador y destino explícito blueflora_dev, verificar primero base/usuario/
esquema, head 0003 y propietarios efectivos. No inferir estado a partir de pruebas.
Enumerar owners mediante política interna existente solo para el SELECT de IDs,
restaurar ese contexto y consultar recursos por owner con FORCE RLS activo.

Detectar UUID reclamados por owners distintos entre plants e historiales,
plant_id/plant_ref_id incompatibles, referencias sin owner, jardines/especies no
válidos, revisiones no positivas o al límite BIGINT y fechas no finitas. Una
referencia histórica sin planta es válida: historical_only, sin planta ficticia.
Medir número de filas, imágenes UTF-8 con campos y envoltorios nuevos, tiempo de
backfill/índices/locks y espacio libre. No truncar, corregir fechas o reasignar IDs.
El backfill mide la imagen con las columnas/fechas finales y el envoltorio de un
grupo, usando la longitud máxima de secuencia; bloquea si supera 65536 bytes.
No reemplaza la medición de volumen/duración/espacio de la ventana real.

Auditar ACL efectivos de tabla/columna/PUBLIC, USAGE/CREATE de esquema, propietarios,
FORCE/políticas y funciones. El delta aprobado retira INSERT/DELETE de gardens,
UPDATE(name,description); INSERT de plants y todos sus UPDATE de columna de 0003;
INSERT de ambos historiales. R conserva solo SELECT de recursos, auth intacto y
EXECUTE resource_apply(uuid,text). Ningún acceso directo a las cuatro tablas nuevas.
Cualquier permiso adicional heredado/PUBLIC requiere revisión específica, no un
REVOKE general automático. Confirmar SHA-256 incorporado sin instalar extensiones.

## Corte conjunto propuesto

1. Operador autorizado detiene escritores antiguos, drena requests y pausa escrituras
   administrativas de catálogo/recursos. No mezclar binarios en rolling deployment.
2. Aplicar 0004 y 0005 bajo la misma transacción externa de Alembic. No COMMIT interno,
   autocommit ni índices concurrentes. Validar constraints antes del COMMIT externo.
3. Verificar head/capacidades/ACL con credenciales runtime y arrancar el nuevo binario.
   Su lifespan y cada transacción de recurso verifican capacidades; sin esquema
   compatible no sirven recursos. No hay migración automática ni fallback.
4. Comprobar conjuntamente los ocho escritores y sus recibos/grupos. El binario viejo
   no dispone ya de DML y debe permanecer fuera de servicio; no reotorgarle permisos.

Antes del COMMIT, un fallo revierte ambas migraciones, datos tentativos y permisos.
Si el resultado del COMMIT es incierto, comprobar esquema/ledger antes de decidir.
Después del COMMIT, mantener escritores cerrados si falla el arranque y corregir
hacia delante. Tras recibir operaciones nuevas, no downgrade destructivo ni copia
antigua que pierda ACK, recibos, feed o datos. Una pérdida real de WAL/ACK requiere
procedimiento de desastre, reconciliación y época nueva; no está implementado aquí.
Los downgrade 0004/0005 fallan expresamente en lugar de borrar información.

## Decisiones y límites

El GUC owner_id protege de errores de consultas/relaciones bajo conexión confiable;
no impide que credenciales runtime comprometidas simulen otro owner. El migrador
puede alterar DDL: inmutabilidad no es protección contra un administrador.

Sin endpoints sync, bootstrap, importaciones, instalaciones móviles, purga o
cambios Flutter/Android. No afirmar que blueflora_dev está actualizado o validado.
