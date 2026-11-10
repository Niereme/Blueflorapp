CREATE TABLE __S__.sync_owner_state (
 owner_id uuid PRIMARY KEY REFERENCES __S__.users(id) ON DELETE RESTRICT,
 epoch uuid NOT NULL DEFAULT gen_random_uuid(), last_sequence bigint NOT NULL DEFAULT 0 CHECK(last_sequence>=0));
CREATE TABLE __S__.sync_operations (
 owner_id uuid NOT NULL REFERENCES __S__.sync_owner_state(owner_id) ON DELETE RESTRICT,
 operation_id uuid NOT NULL, format text NOT NULL, canonical_request text NOT NULL,
 fingerprint bytea NOT NULL CHECK(octet_length(fingerprint)=32), action text NOT NULL, entity_id uuid,
 terminal_status text NOT NULL CHECK(terminal_status IN ('applied','conflict','rejected')),
 receipt jsonb NOT NULL, response_status integer NOT NULL, response_body bytea NOT NULL,
 content_type text, location text, etag text, epoch uuid, committed_sequence bigint,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(owner_id,operation_id), CHECK((epoch IS NULL)=(committed_sequence IS NULL)));
CREATE TABLE __S__.sync_change_groups (
 owner_id uuid NOT NULL REFERENCES __S__.sync_owner_state(owner_id) ON DELETE RESTRICT,
 epoch uuid NOT NULL, sequence bigint NOT NULL CHECK(sequence>0), change_id uuid NOT NULL,
 operation_id uuid NOT NULL, images jsonb NOT NULL,
 PRIMARY KEY(owner_id,epoch,sequence), CONSTRAINT uq_group_operation UNIQUE(owner_id,operation_id), CONSTRAINT uq_group_change UNIQUE(owner_id,change_id),
 CHECK(jsonb_typeof(images)='array' AND jsonb_array_length(images) BETWEEN 1 AND 4),
 CHECK(octet_length(convert_to(jsonb_build_object('sequence',sequence::text,'change_id',change_id,'operation_id',operation_id,'entities',images)::text,'UTF8'))<=65536),
 FOREIGN KEY(owner_id,operation_id) REFERENCES __S__.sync_operations(owner_id,operation_id) DEFERRABLE INITIALLY DEFERRED);
ALTER TABLE __S__.sync_operations ADD FOREIGN KEY(owner_id,epoch,committed_sequence)
 REFERENCES __S__.sync_change_groups(owner_id,epoch,sequence) DEFERRABLE INITIALLY DEFERRED;

CREATE FUNCTION __S__.reject_immutable() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
 SET search_path=pg_catalog,pg_temp AS $$ BEGIN RAISE EXCEPTION 'Registro inmutable' USING ERRCODE='42501'; END $$;
REVOKE ALL ON FUNCTION __S__.reject_immutable() FROM PUBLIC;

CREATE FUNCTION __S__.resource_apply(p_operation_id uuid,p_request_canonical text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp SET timezone='UTC' AS $$
DECLARE
 o uuid; capabilities jsonb;
 req jsonb; p jsonb; a text; kind text; act text; target uuid; entity uuid; base bigint;
 prior __S__.sync_operations%ROWTYPE; st __S__.sync_owner_state%ROWTYPE;
 pl __S__.plants%ROWTYPE; g __S__.gardens%ROWTYPE; old jsonb; rep jsonb; fact jsonb;
 images jsonb := '[]'; keys text[]; k text; v jsonb; wanted_garden uuid;
 status integer := 200; code text; tag text; loc text; body bytea; ct text := 'application/json';
 seq bigint; epoch_id uuid; result jsonb; terminal text := 'applied';
 now_at timestamptz; time_value timestamptz; dirty boolean := false;
 trim_chars text := chr(9)||chr(10)||chr(11)||chr(12)||chr(13)||chr(28)||chr(29)||chr(30)||chr(31)||chr(32)||chr(133)||chr(160)||chr(5760)||chr(8192)||chr(8193)||chr(8194)||chr(8195)||chr(8196)||chr(8197)||chr(8198)||chr(8199)||chr(8200)||chr(8201)||chr(8202)||chr(8232)||chr(8233)||chr(8239)||chr(8287)||chr(12288);
 constraint_name text; ch text; nesting integer:=0; quoted boolean:=false; escaped boolean:=false;
BEGIN
 IF (SELECT version_num FROM __S__.alembic_version) IS DISTINCT FROM '0005_mutation_gateway' THEN
  RAISE EXCEPTION 'Esquema incompatible' USING ERRCODE='55000'; END IF;
 -- A partial NULL is never a technical query or a mutation.
 IF (p_operation_id IS NULL) <> (p_request_canonical IS NULL) THEN
  RAISE EXCEPTION 'Argumentos incompletos' USING ERRCODE='22023'; END IF;
 -- Technical path: catalog reads only; no owner parsing, set_config or DML.
 IF p_operation_id IS NULL AND p_request_canonical IS NULL THEN
  capabilities := (__CAPABILITY_QUERY__);
  IF capabilities IS DISTINCT FROM $e4_manifest$__CAPABILITY_MANIFEST__$e4_manifest$::jsonb THEN
   RAISE EXCEPTION 'Capacidades E.4 incompatibles' USING ERRCODE='55000'; END IF;
  RETURN '{"ready":true,"manifest":"e4-r1-pg18"}'::jsonb;
 END IF;
 o := nullif(current_setting('blueflora.owner_id',true),'')::uuid;
 IF o IS NULL OR p_operation_id IS NULL THEN RAISE EXCEPTION 'Contexto requerido' USING ERRCODE='42501'; END IF;
 IF octet_length(convert_to(p_request_canonical,'UTF8'))>65536 THEN RAISE EXCEPTION 'Entrada demasiado grande' USING ERRCODE='22023'; END IF;
 -- Limitar profundidad antes del parser JSON, también para llamadas SQL directas.
 FOR ch IN SELECT unnest(string_to_array(p_request_canonical,NULL)) LOOP
  IF quoted THEN
   IF escaped THEN escaped:=false; ELSIF ch=chr(92) THEN escaped:=true; ELSIF ch='"' THEN quoted:=false; END IF;
  ELSIF ch='"' THEN quoted:=true;
  ELSIF ch IN ('{','[') THEN nesting:=nesting+1; IF nesting>16 THEN RAISE EXCEPTION 'Profundidad inválida' USING ERRCODE='22023'; END IF;
  ELSIF ch IN ('}',']') THEN nesting:=nesting-1; END IF;
 END LOOP;
 req:=p_request_canonical::jsonb;
 IF jsonb_typeof(req)<>'object' OR NOT req ?& ARRAY['format','operation_id','action','target','if_match','payload']
  OR req - ARRAY['format','operation_id','action','target','if_match','payload'] <> '{}'::jsonb
  OR req->>'format' IS DISTINCT FROM 'rest-v1' OR req->>'operation_id' IS DISTINCT FROM p_operation_id::text
  OR jsonb_typeof(req->'payload')<>'object' THEN RAISE EXCEPTION 'Contrato interno inválido' USING ERRCODE='22023'; END IF;
 p:=req->'payload'; a:=req->>'action'; kind:=split_part(a,'.',1); act:=split_part(a,'.',2);
 IF a NOT IN ('garden.create','garden.update','garden.delete','plant.create','plant.update','plant.delete','growth_measurement.create','watering_event.create') OR a IS NULL THEN
  RAISE EXCEPTION 'Acción inválida' USING ERRCODE='22023'; END IF;
 target:=(req->>'target')::uuid;
 IF kind='garden' THEN keys:=ARRAY['name','description'];
 ELSIF kind='plant' THEN keys:=ARRAY['name','garden_id','species_id','species_label','initial_height_m','watering_frequency_days'];
 ELSIF kind='growth_measurement' THEN keys:=ARRAY['measured_at','height_m','diameter_m','diameter_kind','notes'];
 ELSE keys:=ARRAY['occurred_at']; END IF;
 IF act='create' THEN keys:=keys||ARRAY['id']; END IF;
 IF a='plant.create' THEN keys:=keys||ARRAY['last_watered_at']; END IF;
 IF p-keys<>'{}'::jsonb OR (act='delete' AND p<>'{}'::jsonb) OR (act='update' AND p='{}'::jsonb) THEN RAISE EXCEPTION 'Campos inválidos' USING ERRCODE='22023'; END IF;
 IF act IN ('update','delete') THEN
  IF target IS NULL OR req->>'if_match' IS NULL OR req->>'if_match' !~ ('^"bf1-'||kind||'-'||target::text||'-r[1-9][0-9]*"$') THEN RAISE EXCEPTION 'Precondición inválida' USING ERRCODE='22023'; END IF;
  base:=substring(req->>'if_match' from '-r([0-9]+)"$')::bigint;
 ELSE
  IF req->'if_match'<>'null'::jsonb OR ((kind IN ('garden','plant'))<>(target IS NULL)) THEN RAISE EXCEPTION 'Destino inválido' USING ERRCODE='22023'; END IF;
 END IF;
 FOR k,v IN SELECT * FROM jsonb_each(p) LOOP
  IF v='null'::jsonb THEN
   IF k IN ('id','name','watering_frequency_days','measured_at','occurred_at') THEN RAISE EXCEPTION 'Null inválido' USING ERRCODE='22023'; END IF;
  ELSIF k IN ('id','garden_id','species_id') THEN
   IF jsonb_typeof(v)<>'string' OR (v#>>'{}')<>((v#>>'{}')::uuid)::text THEN RAISE EXCEPTION 'UUID inválido' USING ERRCODE='22023'; END IF;
  ELSIF k='watering_frequency_days' THEN
   IF jsonb_typeof(v)<>'number' OR (v#>>'{}')!~'^[0-9]+$' OR (v#>>'{}')::numeric NOT BETWEEN 1 AND 36500 THEN RAISE EXCEPTION 'Frecuencia inválida' USING ERRCODE='22023'; END IF;
  ELSIF k IN ('initial_height_m','height_m','diameter_m') THEN
   IF jsonb_typeof(v)<>'number' OR NOT ((v#>>'{}')::float8>0 AND (v#>>'{}')::float8<'Infinity'::float8) THEN RAISE EXCEPTION 'Medida inválida' USING ERRCODE='22023'; END IF;
  ELSE
   IF jsonb_typeof(v)<>'string' THEN RAISE EXCEPTION 'Texto inválido' USING ERRCODE='22023'; END IF;
   IF (k='name' AND (length(btrim(v#>>'{}',trim_chars))=0 OR (v#>>'{}')<>btrim(v#>>'{}',trim_chars) OR length(v#>>'{}')>200))
    OR (k IN ('description','notes') AND length(v#>>'{}')>4000)
    OR (k='species_label' AND length(v#>>'{}')>250) THEN RAISE EXCEPTION 'Longitud inválida' USING ERRCODE='22023'; END IF;
   IF k IN ('occurred_at','measured_at','last_watered_at') THEN
    time_value:=(v#>>'{}')::timestamptz;
    IF (v#>>'{}')<>to_char(time_value AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') THEN RAISE EXCEPTION 'Fecha inválida' USING ERRCODE='22023'; END IF;
   END IF;
  END IF;
 END LOOP;
 IF act='create' AND kind IN ('garden','plant') AND NOT p?'name' THEN RAISE EXCEPTION 'Nombre requerido' USING ERRCODE='22023'; END IF;
 IF a='plant.create' AND NOT p?'watering_frequency_days' THEN RAISE EXCEPTION 'Frecuencia requerida' USING ERRCODE='22023'; END IF;
 IF kind='watering_event' AND NOT p?'occurred_at' THEN RAISE EXCEPTION 'Fecha requerida' USING ERRCODE='22023'; END IF;
 IF kind='growth_measurement' THEN
  IF NOT p?'measured_at' OR (coalesce(p->'height_m','null')='null' AND coalesce(p->'diameter_m','null')='null')
   OR ((coalesce(p->'diameter_m','null')='null')<>(coalesce(p->'diameter_kind','null')='null'))
   OR (p->>'diameter_kind' IS NOT NULL AND p->>'diameter_kind' NOT IN ('stem','canopy')) THEN RAISE EXCEPTION 'Dimensiones inválidas' USING ERRCODE='22023'; END IF;
 END IF;
 INSERT INTO __S__.sync_owner_state(owner_id) VALUES(o) ON CONFLICT DO NOTHING;
 SELECT * INTO STRICT st FROM __S__.sync_owner_state WHERE owner_id=o FOR UPDATE;
 SELECT * INTO prior FROM __S__.sync_operations WHERE owner_id=o AND operation_id=p_operation_id;
 IF FOUND THEN
  IF prior.fingerprint=sha256(convert_to(p_request_canonical,'UTF8')) AND convert_to(prior.canonical_request,'UTF8')=convert_to(p_request_canonical,'UTF8') THEN
   RETURN jsonb_build_object('status',prior.response_status,'body_hex',encode(prior.response_body,'hex'),'content_type',prior.content_type,'location',prior.location,'etag',prior.etag);
  END IF;
  RETURN jsonb_build_object('status',409,'body_hex',encode(convert_to('{"detail":{"code":"operation_id_reused","message":"La clave ya identifica otra intención."}}','UTF8'),'hex'),'content_type','application/json');
 END IF;
 now_at:=clock_timestamp();
 -- Todo fallo esperado revierte también los cambios tentativos de esta subtransacción.
 BEGIN
  IF kind='plant' AND p->>'garden_id' IS NOT NULL THEN
   wanted_garden:=(p->>'garden_id')::uuid;
   SELECT * INTO g FROM __S__.gardens WHERE id=wanted_garden FOR UPDATE;
   IF NOT FOUND THEN code:='resource_not_found'; status:=404; RAISE SQLSTATE 'BF001'; END IF;
  END IF;
  IF kind='garden' AND act<>'create' THEN
   SELECT * INTO g FROM __S__.gardens WHERE id=target FOR UPDATE;
   IF NOT FOUND THEN code:='resource_not_found'; status:=404; RAISE SQLSTATE 'BF001'; END IF;
   IF act='update' AND g.deleted_at IS NOT NULL THEN code:='resource_not_found'; status:=404; RAISE SQLSTATE 'BF001'; END IF;
   IF g.revision<>base THEN code:='revision_conflict'; status:=412; RAISE SQLSTATE 'BF001'; END IF;
  ELSIF (kind='plant' AND act<>'create') OR kind IN ('watering_event','growth_measurement') THEN
   PERFORM id FROM __S__.plant_identities WHERE id=target FOR UPDATE;
   SELECT * INTO pl FROM __S__.plants WHERE id=target FOR UPDATE;
   IF NOT FOUND THEN code:='resource_not_found'; status:=404; RAISE SQLSTATE 'BF001'; END IF;
   IF act<>'delete' AND pl.deleted_at IS NOT NULL THEN code:='resource_not_found'; status:=404; RAISE SQLSTATE 'BF001'; END IF;
   IF kind='plant' AND pl.revision<>base THEN code:='revision_conflict'; status:=412; RAISE SQLSTATE 'BF001'; END IF;
  END IF;
  IF kind='plant' THEN
   IF wanted_garden IS NOT NULL AND g.deleted_at IS NOT NULL AND (act='create' OR pl.garden_id IS DISTINCT FROM wanted_garden) THEN code:='garden_archived'; status:=409; RAISE SQLSTATE 'BF001'; END IF;
   IF p->>'species_id' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM __S__.species WHERE id=(p->>'species_id')::uuid) THEN code:='resource_not_found'; status:=404; RAISE SQLSTATE 'BF001'; END IF;
  END IF;
  FOR k IN SELECT unnest(ARRAY['occurred_at','measured_at','last_watered_at']) LOOP
   IF (p->>k)::timestamptz>now_at THEN code:='timestamp_in_future'; status:=422; RAISE SQLSTATE 'BF001'; END IF;
  END LOOP;
  entity:=coalesce((p->>'id')::uuid,CASE WHEN act='create' THEN gen_random_uuid() ELSE target END);
  IF kind='garden' THEN
   IF act='create' THEN
    IF EXISTS(SELECT 1 FROM __S__.gardens WHERE id=entity) THEN code:='entity_exists'; status:=409; RAISE SQLSTATE 'BF001'; END IF;
    INSERT INTO __S__.gardens(id,owner_id,name,description) VALUES(entity,o,p->>'name',p->>'description') RETURNING * INTO g; dirty:=true;
   ELSIF act='update' THEN
    old:=to_jsonb(g);
    UPDATE __S__.gardens SET name=CASE WHEN p?'name' THEN p->>'name' ELSE name END,
     description=CASE WHEN p?'description' THEN p->>'description' ELSE description END WHERE id=target RETURNING * INTO g;
    dirty:=old IS DISTINCT FROM to_jsonb(g);
   ELSIF g.deleted_at IS NULL THEN
    UPDATE __S__.gardens SET deleted_at=now_at WHERE id=target RETURNING * INTO g; dirty:=true;
   END IF;
   IF dirty AND act<>'create' THEN UPDATE __S__.gardens SET revision=revision+1,updated_at=now_at WHERE id=target RETURNING * INTO g; END IF;
   rep:=to_jsonb(g)-'owner_id';
  ELSIF kind='plant' THEN
   IF act='create' THEN
    IF EXISTS(SELECT 1 FROM __S__.plant_identities WHERE id=entity) THEN code:='entity_exists'; status:=409; RAISE SQLSTATE 'BF001'; END IF;
    INSERT INTO __S__.plant_identities(id,owner_id,state,revision) VALUES(entity,o,'full',1);
    INSERT INTO __S__.plants(id,owner_id,name,garden_id,species_id,species_label,initial_height_m,watering_frequency_days,last_watered_at,baseline_last_watered_at,baseline_source)
     VALUES(entity,o,p->>'name',(p->>'garden_id')::uuid,(p->>'species_id')::uuid,p->>'species_label',(p->>'initial_height_m')::float8,(p->>'watering_frequency_days')::integer,(p->>'last_watered_at')::timestamptz,(p->>'last_watered_at')::timestamptz,CASE WHEN p->>'last_watered_at' IS NULL THEN 'unknown' ELSE 'declared_initial' END) RETURNING * INTO pl;
    dirty:=true;
   ELSIF act='update' THEN
    old:=to_jsonb(pl);
    UPDATE __S__.plants SET name=CASE WHEN p?'name' THEN p->>'name' ELSE name END,
     garden_id=CASE WHEN p?'garden_id' THEN (p->>'garden_id')::uuid ELSE garden_id END,
     species_id=CASE WHEN p?'species_id' THEN (p->>'species_id')::uuid ELSE species_id END,
     species_label=CASE WHEN p?'species_label' THEN p->>'species_label' ELSE species_label END,
     initial_height_m=CASE WHEN p?'initial_height_m' THEN (p->>'initial_height_m')::float8 ELSE initial_height_m END,
     watering_frequency_days=CASE WHEN p?'watering_frequency_days' THEN (p->>'watering_frequency_days')::integer ELSE watering_frequency_days END
     WHERE id=target RETURNING * INTO pl;
    dirty:=old IS DISTINCT FROM to_jsonb(pl);
   ELSIF pl.deleted_at IS NULL THEN
    UPDATE __S__.plants SET deleted_at=now_at WHERE id=target RETURNING * INTO pl; dirty:=true;
   END IF;
   IF dirty AND act<>'create' THEN UPDATE __S__.plants SET revision=revision+1,updated_at=now_at WHERE id=target RETURNING * INTO pl; END IF;
   IF dirty THEN UPDATE __S__.plant_identities SET revision=pl.revision WHERE id=entity; END IF;
   rep:=to_jsonb(pl)-ARRAY['owner_id','baseline_last_watered_at','baseline_source'];
  ELSE
   IF kind='watering_event' THEN
    SELECT to_jsonb(t)-ARRAY['owner_id','id','plant_id','plant_name_snapshot','recorded_at','event_type'] INTO fact FROM __S__.watering_events t WHERE id=entity;
    IF FOUND THEN
     IF fact<>jsonb_build_object('plant_ref_id',target,'occurred_at',(p->>'occurred_at')::timestamptz) THEN code:='entity_content_mismatch'; status:=409; RAISE SQLSTATE 'BF001'; END IF;
    ELSE
     INSERT INTO __S__.watering_events(id,owner_id,plant_id,plant_ref_id,plant_name_snapshot,occurred_at) VALUES(entity,o,target,target,pl.name,(p->>'occurred_at')::timestamptz); dirty:=true;
    END IF;
    IF dirty AND (pl.last_watered_at IS NULL OR (p->>'occurred_at')::timestamptz>pl.last_watered_at) THEN
     UPDATE __S__.plants SET last_watered_at=(p->>'occurred_at')::timestamptz,revision=revision+1,updated_at=now_at WHERE id=target RETURNING * INTO pl;
     UPDATE __S__.plant_identities SET revision=pl.revision WHERE id=target;
     -- Imagen planta protocolar, baseline incluido; fechas normalizadas debajo.
     images:=jsonb_build_array(jsonb_build_object('type','plant','state',to_jsonb(pl)-'owner_id'));
    END IF;
    SELECT to_jsonb(t)-'owner_id' INTO rep FROM __S__.watering_events t WHERE id=entity;
   ELSE
    SELECT to_jsonb(t)-ARRAY['owner_id','id','plant_id','plant_name_snapshot','recorded_at'] INTO fact FROM __S__.growth_history t WHERE id=entity;
    IF FOUND THEN
     IF fact<>jsonb_build_object('plant_ref_id',target,'measured_at',(p->>'measured_at')::timestamptz,'height_m',(p->>'height_m')::float8,'diameter_m',(p->>'diameter_m')::float8,'diameter_kind',p->>'diameter_kind','notes',p->>'notes') THEN code:='entity_content_mismatch'; status:=409; RAISE SQLSTATE 'BF001'; END IF;
    ELSE
     INSERT INTO __S__.growth_history(id,owner_id,plant_id,plant_ref_id,plant_name_snapshot,measured_at,height_m,diameter_m,diameter_kind,notes) VALUES(entity,o,target,target,pl.name,(p->>'measured_at')::timestamptz,(p->>'height_m')::float8,(p->>'diameter_m')::float8,p->>'diameter_kind',p->>'notes'); dirty:=true;
    END IF;
    SELECT to_jsonb(t)-'owner_id' INTO rep FROM __S__.growth_history t WHERE id=entity;
   END IF;
   rep:=rep||jsonb_build_object('revision','1');
  END IF;
  -- Una sola representación REST, con campos almacenados y fechas deterministas.
  IF kind IN ('garden','plant') THEN rep:=rep||jsonb_build_object('revision',rep->>'revision'); END IF;
  FOR k IN SELECT unnest(ARRAY['created_at','updated_at','deleted_at','recorded_at','occurred_at','measured_at','last_watered_at']) LOOP
   IF rep->>k IS NOT NULL THEN rep:=jsonb_set(rep,ARRAY[k],to_jsonb(to_char((rep->>k)::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))); END IF;
  END LOOP;
  tag:='"bf1-'||CASE kind WHEN 'growth_measurement' THEN 'growth' WHEN 'watering_event' THEN 'watering' ELSE kind END||'-'||entity::text||'-r'||(rep->>'revision')||'"';
  IF dirty THEN
   IF kind='plant' THEN old:=to_jsonb(pl)-'owner_id'; ELSE old:=rep; END IF;
   images:=images||jsonb_build_array(jsonb_build_object('type',kind,'state',old));
   -- Normalizar TODAS las imágenes; la revisión nunca es número JSON.
   FOR i IN 0..jsonb_array_length(images)-1 LOOP
    old:=images->i->'state'; old:=old||jsonb_build_object('revision',old->>'revision');
    FOR k IN SELECT unnest(ARRAY['created_at','updated_at','deleted_at','recorded_at','occurred_at','measured_at','last_watered_at','baseline_last_watered_at']) LOOP
     IF old->>k IS NOT NULL THEN old:=jsonb_set(old,ARRAY[k],to_jsonb(to_char((old->>k)::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))); END IF;
    END LOOP;
    images:=jsonb_set(images,ARRAY[i::text],jsonb_build_object('entity_type',images->i->>'type','entity_id',old->>'id','revision',old->>'revision','state',old-'revision'));
   END LOOP;
   IF octet_length(convert_to(jsonb_build_object('sequence',(st.last_sequence+1)::text,'change_id','00000000-0000-0000-0000-000000000000'::text,'operation_id',p_operation_id,'entities',images)::text,'UTF8'))>65536 THEN code:='image_too_large'; status:=422; RAISE SQLSTATE 'BF001'; END IF;
  END IF;
  IF act='delete' THEN status:=204; body:=''::bytea; ct:=NULL;
  ELSE
   status:=CASE WHEN act='create' THEN 201 ELSE 200 END;
   body:=convert_to(rep::text,'UTF8');
  END IF;
  IF act='create' THEN loc:='/api/v1/'||CASE kind WHEN 'garden' THEN 'gardens' WHEN 'plant' THEN 'plants' WHEN 'watering_event' THEN 'watering-events' ELSE 'growth-history' END||'/'||entity::text; END IF;
 EXCEPTION
  WHEN SQLSTATE 'BF001' THEN
   dirty:=false; images:='[]'; tag:=NULL; loc:=NULL; ct:='application/json';
   terminal:=CASE WHEN status IN (409,412) THEN 'conflict' ELSE 'rejected' END;
   rep:=jsonb_build_object('detail',jsonb_build_object('code',code,'message','La operación no se puede aplicar.'));
   IF code='timestamp_in_future' THEN rep:=rep||jsonb_build_object('server_time',to_char(now_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')); END IF;
   body:=convert_to(rep::text,'UTF8');
  WHEN unique_violation THEN
   GET STACKED DIAGNOSTICS constraint_name=CONSTRAINT_NAME;
   IF constraint_name NOT IN ('pk_gardens','pk_plants','plant_identities_pkey','pk_growth_history','pk_watering_events') THEN RAISE; END IF;
   dirty:=false; images:='[]'; tag:=NULL; loc:=NULL; status:=409; terminal:='rejected'; ct:='application/json';
   body:=convert_to('{"detail":{"code":"identity_unavailable","message":"Identidad no disponible."}}','UTF8');
 END;
 IF dirty THEN
  UPDATE __S__.sync_owner_state SET last_sequence=last_sequence+1 WHERE owner_id=o RETURNING last_sequence,epoch INTO seq,epoch_id;
  INSERT INTO __S__.sync_change_groups(owner_id,epoch,sequence,change_id,operation_id,images) VALUES(o,epoch_id,seq,gen_random_uuid(),p_operation_id,images);
 END IF;
 result:=jsonb_build_object('status',status,'body_hex',encode(body,'hex'),'content_type',ct,'location',loc,'etag',tag);
 INSERT INTO __S__.sync_operations(owner_id,operation_id,format,canonical_request,fingerprint,action,entity_id,terminal_status,receipt,response_status,response_body,content_type,location,etag,epoch,committed_sequence)
 VALUES(o,p_operation_id,'rest-v1',p_request_canonical,sha256(convert_to(p_request_canonical,'UTF8')),a,entity,terminal,result,status,body,ct,loc,tag,epoch_id,seq);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION __S__.resource_apply(uuid,text) FROM PUBLIC;
