# Invariantes verificables y matriz de pruebas

Esta es una MATRIZ PROPUESTA, no tests añadidos/ejecutados. Las 158 pruebas previas
se preservarán; cambios de expectativas por contrato deben documentarse, sin
eliminar cobertura ni afirmar que pasaron sin ejecutarlas.

## 1. Invariantes

| ID | Obligación verificable |
| --- | --- |
| I01 | UUID válido estable durante edición, reintento, reinicio y vinculación al mismo propietario |
| I02 | Nombre/especie no determina identidad; duplicados de nombre son entidades distintas |
| I03 | Todo cambio confirmado por UI tiene entidad/evento y comando durables en un único COMMIT local |
| I04 | Nunca hay comando confirmado sin su cambio local ni cambio sincronizable sin comando |
| I05 | Operación intentada conserva ID/envelope/fingerprint; cambio de intención crea nueva operación |
| I06 | Una operación en vuelo por entidad; dependencias previas confirmadas, DAG sin ciclos |
| I07 | Revisión comparada en la misma transacción del cambio; no gana el reloj del dispositivo |
| I08 | Datos, recibo y grupo incremental se confirman o revierten juntos |
| I09 | Mismo operation_id/contenido produce un solo efecto y recibo reproducible |
| I10 | Recibo anterior se consulta antes de CAS; respuesta perdida no duplica ni transforma éxito en conflicto |
| I11 | Cursor solo avanza junto a cambios aplicados contiguamente; ACK push no lo adelanta |
| I12 | No sobrescribir shadow/proyección nueva con ACK antiguo; conservar borradores posteriores |
| I13 | Imágenes de cambio y snapshots son inmutables; página no divide un grupo |
| I14 | Solo tombstone explícito elimina de vista activa; ausencia/timeout/401/página vacía no borra datos |
| I15 | Edición contra eliminación conserva copia/conflicto, no restaura sin decisión |
| I16 | Eventos manuales e historial de crecimiento no se borran con planta, ni se inventan desde baseline |
| I17 | Orden incremental sigue confirmación, no occurred_at/measured_at/updated_at |
| I18 | RLS USING/WITH CHECK y FK compuestas impiden acceso/relación entre propietarios |
| I19 | Cola, shadow, conflictos, cursores y respuestas pertenecen a un espacio+cuenta+servidor+época |
| I20 | Logout/cambio de cuenta no destruye información ni permite enviar/aplicar datos con otro sujeto |
| I21 | Importación requiere selección/consentimiento durable; login solo no sube nada |
| I22 | SQLite activo y respaldo original no son dos fuentes editables; marcador activo es transaccional |
| I23 | Cada fuente incompatible tiene original recuperable y diagnóstico; sin truncar, descartar o adivinar |
| I24 | REST y sync pasan por CAS/ledger/feed comunes; ningún escritor elude el protocolo |
| I25 | Fechas nuevas UTC con offset; regla calendario sigue siendo 86400 segundos |
| I26 | Baseline no es evidencia de riego; manual no significa bomba ni agua físicamente verificada |
| I27 | Tokens no aparecen en SQLite/SharedPreferences/imports/logs/reportes; vault y DB no se asumen atómicos |
| I28 | No hay acceso API a datos ajenos, escritura de catálogo, DDL o privilegios generales sobre tablas futuras |
| I29 | Ninguna confirmación de import completo si faltan registros; cancel no borra aplicados |
| I30 | Retención no rompe la repetición de operaciones de dispositivos desconectados |

## 2. Matriz mínima de aceptación

| Caso | Preparación / fallo inyectado | Resultado / evidencia | Invariantes |
| --- | --- | --- | --- |
| M01 | PlantSnapshot v1 con UUID, nulls, coma ya parseada, eventos | Recuentos y todos los campos iguales; IDs idénticos | I01,I22 |
| M02 | Formato legado sin UUID/frecuencia moderna | Mapa asignado una sola vez; frecuencia solo si inequívoca | I01,I23 |
| M03 | Clave ausente vs lista vacía | Primera apertura distinta de jardín vacío; no semilla repetida | I14,I22 |
| M04 | JSON roto/versión desconocida | Bloquea activación, preserva raw y fuente; no snapshot vacío | I23 |
| M05 | UUID inválidos/duplicados, nombre largo/especie larga | Ninguna fila reemplazada; recovery explícito | I02,I23 |
| M06 | Fecha sin offset, DST ambiguo/inexistente, cambio de zona | Raw intacto, decisión guardada; no conversión silenciosa | I23,I25 |
| M07 | NaN/Infinity/bool/negativos y driver NaN→NULL | Rechazo antes de bind, original recuperable | I23 |
| M08 | Eventos de plantas faltantes y renombradas | UUID/nombre histórico exactos; referencias sin plantas ficticias | I16 |
| M09 | Cierre tras cada COMMIT de captura/mapa/staging/verificación/activación | Reanuda desde marcador correcto, sin nuevos UUID ni pérdida | I01,I22 |
| M10 | Migración repetida idéntica y fuente cambiada después de fallo | No duplica; fuente nueva tiene backup/run nuevo | I09,I22 |
| M11 | Disco lleno/SQLite ocupado/backup corrupto | No confirma UI ni activa candidato; fuente anterior intacta | I03,I23 |
| M12 | Edición posterior a activar SQLite y app antigua/restauración | No reutiliza JSON viejo; recuperación conserva edición y cola | I22 |
| L01 | Agregar/editar/eliminar/regar sin red, cerrar proceso | Cambios/eventos/comandos sobreviven y UI funcional | I03,I04 |
| L02 | Fallo al insertar outbox o evento | Ninguna escritura parcial ni éxito visual | I03,I04 |
| L03 | Borrador B mientras A está en vuelo; llega ACK A tarde | B sigue visible y pendiente; base A actualizada sin reemplazar B | I12 |
| L04 | Dos workers/instancias y un refresh | Exclusión o fallo cerrado; nunca dos refresh consumidos | I06,I27 |
| P01 | Timeout antes de recepción y después de COMMIT | Repetición mismo ID, un solo efecto | I08,I09 |
| P02 | Mismo ID con payload distinto, y mismo UUID entidad con otra operación | Error explícito, no sobrescritura/duplicado | I05,I09 |
| P03 | Cierre servidor entre dato/recibo/grupo antes de COMMIT | Rollback de los tres; reintento correcto | I08 |
| P04 | Lote mixto aplicado/conflicto/bloqueado y corte intermedio | Progreso por recibos, no suponer rollback de todo el lote | I08,I10 |
| P05 | Dos ediciones misma revisión, dos dispositivos | Solo una CAS; otra conserva conflicto local | I07,I15 |
| P06 | Campos disjuntos, iguales y mismo campo diferente | Merge solo inequívoco; nuevo CAS con nuevo ID | I07,I12 |
| P07 | Riego antiguo recibido tarde y dos riegos simultáneos | Ambos eventos; fecha derivada no retrocede; feed los incluye | I16,I17 |
| P08 | Misma operación de riego concurrente y tras renombrar | Un evento y snapshot original, sin recomputarlo en retry | I09,I16 |
| P09 | Borrado remoto contra edición/riego offline | Edición conserva conflicto; riego conserva historia sin restaurar | I15,I16 |
| C01 | Paginación con escrituras concurrentes y fechas empatadas | Sin huecos; secuencias confirmadas y grupos indivisibles | I11,I13,I17 |
| C02 | Transacción con secuencia anterior bloqueada, posterior intenta confirmar | Contador por propietario serializa; no cursor adelantado | I17 |
| C03 | Cambio REST mientras otro dispositivo hace push/pull | Mismo feed/revisión, 428/412 correctos | I24 |
| C04 | Crash entre aplicar datos y cursor | Ambos rollback o ambos commit; página repetible | I11 |
| C05 | ACK propio con secuencia alta y cambios ajenos anteriores | ACK no salta cambios ajenos; pull mantiene continuidad | I11 |
| C06 | Cursor ajeno, malformado, época restaurada | 404/400/410 sin filtrar datos; bootstrap mantiene pendientes | I18,I19 |
| B01 | Snapshot multipágina con cambios durante descarga | Foto consistente y cambios posteriores desde corte | I13 |
| B02 | Página duplicada/faltante/TTL agotado/cuota | No activa incompleto ni borra datos; reinicio seguro | I14 |
| B03 | Bootstrap nuevo con registros ausentes y outbox sucio | Recuperación/conflicto, no DELETE implícito | I14,I15 |
| B04 | Catálogo cambia versión | Rebootstrap fijo conserva species_id/labels y cola | I12 |
| A01 | Dos usuarios con IDs conocidos, cursor y relaciones cruzados | RLS con rol API real; 404 genérico y sin estado ajeno | I18,I28 |
| A02 | owner_id/recorded_at/revision internos en payload | Rechazo; identidad solo desde token | I18 |
| A03 | API intenta DDL/SET ROLE/leer hashes/modificar especies/borrar planta | Denegación bajo rol runtime, sin fallback | I28 |
| A04 | Cambio A→B con request A en vuelo | No se envía/aplica en B, outbox A intacto | I19,I20 |
| A05 | Logout offline y reinicio | Datos conservados, A bloqueado, anónimo utilizable | I20 |
| A06 | Refresh responde perdido y cierre entre vault/DB | needs_login sin reusar refresh incierto; cola intacta | I27 |
| A07 | SQL/log/error/report de validación con secretos sintéticos | No aparecen tokens/inputs sensibles | I27 |
| A08 | Vault ausente, cuenta previa cerrada o server_instance_id cambiado | Fallo cerrado, no borrar DB ni abrir cuenta equivocada | I19,I20 |
| IM01 | Login sin consentimiento / selección parcial | Cero subidas espontáneas; solo selección confirmada | I21 |
| IM02 | Manifiesto/hash/count incorrectos, record_index repetido diferente | 409/needs_review, no publicación silenciosa | I23,I29 |
| IM03 | Reintentos de stage/commit con respuesta perdida | Mismo request/operation ID; recibos recuperados | I09 |
| IM04 | Colisión propia distinta/ajena antes o durante commit | No sobrescribe ni vincula a otro; aplicado previo queda explícito | I18,I29 |
| IM05 | Cancel/TTL antes y durante publicación | Cancela pendientes, conserva aplicados y fuente local | I29 |
| IM06 | Import huérfano y nombre anterior a renombrado | Referencia reservada por propietario, snapshot exacto | I16 |
| N01 | Resync, cuenta cambiada, riego remoto y preferencia de hora | Cancela avisos previos y recalcula tras COMMIT sin duplicar | I25 |
| N02 | Sin fecha, baseline de registro, hora adelantada/atrasada | No humedad/bomba ficticia; calendario consistente | I25,I26 |
| X01 | Android cierre forzado/SQLite recovery/disco lleno | Evidencia instrumentada de durabilidad bajo perfil aprobado | I03,I22 |
| X02 | Linux/Windows/iOS/macOS por adaptador | DAO y vault verificados por plataforma, sin asumir cobertura | I27 |
| X03 | Web dos pestañas/expulsión de almacenamiento/worker ausente | No habilitar garantías hasta validación; sin pérdida oculta | I22 |

## 3. Criterios para autorizar 3.2E.2

Debe quedar aprobado explícitamente:

- Protocolo v1 y límites; importaciones de progreso parcial; semántica de conflictos
  y del snapshot, sin asumir que esta aprobación autoriza migraciones de servidor.
- Esquema local, uso de SQLite y adaptadores/versiones para Android/Linux. Inventario
  de dependencias nativas y decisión separada sobre las demás plataformas/web.
- Migración anónima con respaldo permanente en sandbox, reglas de fechas/IDs y
  bloqueo de activación ante incompatibilidades no resueltas.
- Estrategia de privacidad: alcance de sandbox/aislamiento lógico y aprobación
  separada de cifrado antes de cuentas reales. No inventar protección inexistente.
- Mantener o revisar explícitamente el ejemplo de primera apertura.

La entrega de 3.2E.2 estará completa solo si: repositorio SQLite funciona offline,
no hay HTTP ni tokens ni cambios de PostgreSQL, pruebas anteriores mantienen su
cobertura, M01–M12/L01–L02 pasan y X01 tiene evidencia Android real o limitación
pendiente expresamente declarada. Un fallo no elimina ni reinicia preferencias.
La migración es recuperable al reiniciar y un segundo pase no duplica información.
No instalar paquetes, tocar archivos Flutter ni comenzar 3.2E.2 por el mero hecho
de haber generado esta documentación.
