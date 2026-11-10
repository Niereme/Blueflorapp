-- Exact catalog projection for the frozen PostgreSQL 18 E.4-R1 contract. No data reads.
WITH scope AS (
 SELECT c.* FROM pg_class c WHERE c.relnamespace=to_regnamespace('__SCHEMA__')
 AND c.relname IN ('users','species','gardens','plants','growth_history','watering_events','plant_identities','sync_owner_state','sync_operations','sync_change_groups','auth_sessions','auth_refresh_tokens','auth_rate_limits','alembic_version')
), diameter_rule AS (
 SELECT $e4_diameter$__DIAMETER_CONTRACT__$e4_diameter$::jsonb AS rule
), approved_diameter AS (
 SELECT k.oid FROM pg_constraint k JOIN scope c ON c.oid=k.conrelid
 CROSS JOIN diameter_rule d
 WHERE c.relname=d.rule->>'table' AND k.conname=d.rule->>'name'
 AND k.contype='c' AND k.convalidated AND k.conenforced
 AND NOT k.condeferrable AND NOT k.condeferred AND NOT k.connoinherit
 AND k.conislocal AND k.coninhcount=0
 AND pg_get_expr(k.conbin,k.conrelid,false) IN (d.rule->>'original',d.rule->>'reconstructed')
 AND k.conkey=ARRAY(SELECT a.attnum FROM unnest(ARRAY['diameter_m','diameter_kind']) WITH ORDINALITY n(name,ord)
   JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname=n.name AND NOT a.attisdropped ORDER BY n.ord)
 AND (SELECT count(*)=2 AND bool_and(
   format_type(a.atttypid,a.atttypmod)=d.rule->'columns'->a.attname->>'type'
   AND NOT a.attnotnull AND a.attidentity='' AND a.attgenerated=''
   AND NOT EXISTS(SELECT 1 FROM pg_attrdef ad WHERE ad.adrelid=c.oid AND ad.adnum=a.attnum)
   AND CASE WHEN a.attname='diameter_m' THEN a.attcollation=0
       ELSE a.attcollation='pg_catalog."default"'::regcollation END)
   FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum=ANY(k.conkey) AND NOT a.attisdropped)
), tables AS (
 SELECT c.relname, jsonb_build_object(
 'kind',c.relkind,'owner',CASE WHEN pg_get_userbyid(c.relowner)='__OWNER__' THEN 'M' ELSE pg_get_userbyid(c.relowner) END,
 'rls',c.relrowsecurity,'force',c.relforcerowsecurity,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid,false),
 'runtime',(SELECT coalesce(jsonb_agg(priv.value ORDER BY priv.value) FILTER(WHERE has_column_privilege('__RUNTIME__',c.oid,a.attnum,priv.value)),'[]'::jsonb) FROM unnest(ARRAY['SELECT','INSERT','UPDATE','REFERENCES','SELECT WITH GRANT OPTION','INSERT WITH GRANT OPTION','UPDATE WITH GRANT OPTION','REFERENCES WITH GRANT OPTION']) priv(value)),
 'acl',(SELECT coalesce(jsonb_agg(jsonb_build_array(CASE WHEN x.grantee=0 THEN 'PUBLIC' WHEN x.grantee=c.relowner THEN 'M' WHEN pg_get_userbyid(x.grantee)='__RUNTIME__' THEN 'R' ELSE pg_get_userbyid(x.grantee) END,x.privilege_type,x.is_grantable) ORDER BY x.grantee=0,x.privilege_type,pg_get_userbyid(x.grantee)), '[]'::jsonb) FROM aclexplode(a.attacl) x)
 ) || CASE WHEN c.relname='growth_history' AND a.attname IN ('diameter_m','diameter_kind') THEN jsonb_build_object('collation',CASE WHEN a.attcollation=0 THEN NULL ELSE (SELECT n.nspname||'.'||co.collname FROM pg_collation co JOIN pg_namespace n ON n.oid=co.collnamespace WHERE co.oid=a.attcollation) END) ELSE '{}'::jsonb END ORDER BY a.attname) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'runtime',(SELECT coalesce(jsonb_agg(priv.value ORDER BY priv.value) FILTER(WHERE has_table_privilege('__RUNTIME__',c.oid,priv.value)),'[]'::jsonb) FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN','SELECT WITH GRANT OPTION','INSERT WITH GRANT OPTION','UPDATE WITH GRANT OPTION','DELETE WITH GRANT OPTION','TRUNCATE WITH GRANT OPTION','REFERENCES WITH GRANT OPTION','TRIGGER WITH GRANT OPTION','MAINTAIN WITH GRANT OPTION']) priv(value)),
 'acl',(SELECT coalesce(jsonb_agg(jsonb_build_array(CASE WHEN x.grantee=0 THEN 'PUBLIC' WHEN x.grantee=c.relowner THEN 'M' WHEN pg_get_userbyid(x.grantee)='__RUNTIME__' THEN 'R' ELSE pg_get_userbyid(x.grantee) END,x.privilege_type,x.is_grantable) ORDER BY x.grantee=0,x.privilege_type,pg_get_userbyid(x.grantee)), '[]'::jsonb) FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x),
 'constraints',(SELECT coalesce(jsonb_agg(z.v ORDER BY z.v::text),'[]'::jsonb) FROM (SELECT jsonb_build_object('type',k.contype,'columns',(SELECT jsonb_agg(a.attname ORDER BY u.ord) FROM unnest(k.conkey) WITH ORDINALITY u(num,ord) JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=u.num),
 'ref_table',r.relname,'ref_local',CASE WHEN r.oid IS NULL THEN NULL ELSE r.relnamespace=c.relnamespace END,'ref_columns',(SELECT jsonb_agg(a.attname ORDER BY u.ord) FROM unnest(k.confkey) WITH ORDINALITY u(num,ord) JOIN pg_attribute a ON a.attrelid=k.confrelid AND a.attnum=u.num),
 'update',k.confupdtype,'delete',k.confdeltype,'match',k.confmatchtype,'deferrable',k.condeferrable,'deferred',k.condeferred,'validated',k.convalidated,'enforced',k.conenforced,'expression',CASE WHEN k.oid IN (SELECT oid FROM approved_diameter) THEN (SELECT rule->>'original' FROM diameter_rule) ELSE pg_get_expr(k.conbin,k.conrelid,false) END,
 'index_valid',i.indisvalid,'index_ready',i.indisready,'index_unique',i.indisunique,'index_immediate',i.indimmediate,'nulls_not_distinct',i.indnullsnotdistinct) v FROM pg_constraint k LEFT JOIN pg_class r ON r.oid=k.confrelid LEFT JOIN pg_index i ON i.indexrelid=k.conindid WHERE k.conrelid=c.oid) z),
 'policies',(SELECT coalesce(jsonb_agg(jsonb_build_object('command',p.polcmd,'permissive',p.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN u=0 THEN 'PUBLIC' WHEN pg_get_userbyid(u)='__OWNER__' THEN 'M' ELSE pg_get_userbyid(u) END ORDER BY u=0,pg_get_userbyid(u)) FROM unnest(p.polroles) u),'using',pg_get_expr(p.polqual,p.polrelid,false),'check',pg_get_expr(p.polwithcheck,p.polrelid,false)) ORDER BY p.polname),'[]'::jsonb) FROM pg_policy p WHERE p.polrelid=c.oid),
 'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_object('type',t.tgtype,'enabled',t.tgenabled,'function',f.proname,'function_local',f.pronamespace=c.relnamespace,'args',encode(t.tgargs,'hex'),'columns',t.tgattr::text,'when',pg_get_expr(t.tgqual,t.tgrelid,false),'constraint',t.tgconstraint<>0,'deferrable',t.tgdeferrable,'deferred',t.tginitdeferred) ORDER BY t.tgname),'[]'::jsonb) FROM pg_trigger t JOIN pg_proc f ON f.oid=t.tgfoid WHERE t.tgrelid=c.oid AND NOT t.tgisinternal)
 ) value FROM scope c
), functions AS (
 SELECT p.proname, jsonb_build_object('arguments',pg_get_function_identity_arguments(p.oid),'return',format_type(p.prorettype,NULL),'owner',CASE WHEN pg_get_userbyid(p.proowner)='__OWNER__' THEN 'M' ELSE pg_get_userbyid(p.proowner) END,
 'language',l.lanname,'definer',p.prosecdef,'config',(SELECT jsonb_agg(cfg.setting ORDER BY cfg.setting) FROM unnest(p.proconfig) cfg(setting)),'kind',p.prokind,'strict',p.proisstrict,'volatile',p.provolatile,'leakproof',p.proleakproof,'set',p.proretset,'defaults',p.pronargdefaults,
 'runtime',has_function_privilege('__RUNTIME__',p.oid,'EXECUTE'),'runtime_grant',has_function_privilege('__RUNTIME__',p.oid,'EXECUTE WITH GRANT OPTION'),
 'acl',(SELECT jsonb_agg(jsonb_build_array(CASE WHEN x.grantee=0 THEN 'PUBLIC' WHEN x.grantee=p.proowner THEN 'M' WHEN pg_get_userbyid(x.grantee)='__RUNTIME__' THEN 'R' ELSE pg_get_userbyid(x.grantee) END,x.privilege_type,x.is_grantable) ORDER BY x.grantee=0,x.privilege_type,pg_get_userbyid(x.grantee)) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x),
 'body',CASE WHEN p.proname='reject_immutable' THEN p.prosrc ELSE NULL END) value
 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.pronamespace=to_regnamespace('__SCHEMA__') AND p.proname IN ('resource_apply','reject_immutable','auth_lookup','auth_register','auth_start_session','auth_access','auth_rotate','auth_logout','auth_attempt')
)
SELECT jsonb_build_object('diameter_check_contract',(SELECT count(*)=1 FROM approved_diameter),'postgres_major',current_setting('server_version_num')::int/10000,
 'schema_owner_valid',EXISTS(SELECT 1 FROM pg_namespace n JOIN pg_database d ON d.datname=current_database() WHERE n.oid=to_regnamespace('__SCHEMA__') AND (pg_get_userbyid(n.nspowner)='__OWNER__' OR (n.nspname='public' AND pg_get_userbyid(n.nspowner)='pg_database_owner' AND pg_get_userbyid(d.datdba)='__OWNER__'))),
 'roles',(SELECT jsonb_object_agg(CASE WHEN rolname='__OWNER__' THEN 'M' ELSE 'R' END,jsonb_build_object('login',rolcanlogin,'super',rolsuper,'bypass',rolbypassrls,'createdb',rolcreatedb,'createrole',rolcreaterole,'replication',rolreplication,'inherit',rolinherit,'memberships',(SELECT count(*) FROM pg_auth_members m WHERE m.member=r.oid))) FROM pg_roles r WHERE rolname IN ('__OWNER__','__RUNTIME__')),
 'runtime_database_create',has_database_privilege('__RUNTIME__',current_database(),'CREATE'),
 'builtins',(SELECT jsonb_object_agg(f,coalesce(has_function_privilege('__OWNER__',to_regprocedure(f),'EXECUTE') AND has_function_privilege('__RUNTIME__',to_regprocedure(f),'EXECUTE'),false)) FROM unnest(ARRAY['pg_catalog.sha256(bytea)','pg_catalog.gen_random_uuid()']) f),
 'tables',(SELECT jsonb_object_agg(relname,value) FROM tables),
 'functions',(SELECT jsonb_agg(jsonb_build_array(proname,value) ORDER BY proname,value::text) FROM functions),
 'schema_runtime_usage',has_schema_privilege('__RUNTIME__','__SCHEMA__','USAGE'),
 'schema_runtime_create',has_schema_privilege('__RUNTIME__','__SCHEMA__','CREATE'),
 'schema_public_create',EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a WHERE n.oid=to_regnamespace('__SCHEMA__') AND a.grantee=0 AND a.privilege_type='CREATE'))
