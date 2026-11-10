"""Focused CHECK diagnostic; only disposable blueflora_test schemas.

No production manifest/comparator changes and no access to the preserved clone.
"""
import json
import math
import os
from pathlib import Path
import re
import subprocess
from uuid import uuid4

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from app.core.config import Settings
from app.db.connection import create_database_engine, verify_database, DatabaseConfigurationError
from app.modules.common.repository import ResourceRepository
from test_auth import auth_db

pytestmark=pytest.mark.postgres
NAME='ck_growth_history_diameter_kind'
RAW="(diameter_m IS NULL AND diameter_kind IS NULL) OR (diameter_m IS NOT NULL AND diameter_kind IS NOT NULL AND diameter_kind IN ('stem', 'canopy'))"
ORIGINAL="(((diameter_m IS NULL) AND (diameter_kind IS NULL)) OR ((diameter_m IS NOT NULL) AND (diameter_kind IS NOT NULL) AND ((diameter_kind)::text = ANY ((ARRAY['stem'::character varying, 'canopy'::character varying])::text[]))))"
RESTORED="(((diameter_m IS NULL) AND (diameter_kind IS NULL)) OR ((diameter_m IS NOT NULL) AND (diameter_kind IS NOT NULL) AND ((diameter_kind)::text = ANY (ARRAY[('stem'::character varying)::text, ('canopy'::character varying)::text]))))"
FINITE="diameter_m IS NULL OR (diameter_m > 0 AND diameter_m < 'Infinity'::double precision)"
KINDS=[None,'stem','canopy','invalid','','STEM','Canopy',' stem','stem ','canopy ',' stem ','\tstem','stem\n']
DIAMETERS=[None,-math.inf,-1.0,-0.0,5e-324,1.0,math.inf,math.nan]


def meta(c,schema,table):
    return c.execute(text("""SELECT pg_get_expr(conbin,conrelid,false) expression,
        pg_get_constraintdef(oid,false) definition,conbin::text tree,
        convalidated,conenforced,condeferrable,condeferred
        FROM pg_constraint WHERE conrelid=to_regclass(:table) AND conname=:name"""),
        {'table':f'"{schema}".{table}','name':NAME}).mappings().one()


@pytest.fixture
def focused():
    settings=Settings()
    if settings.test_database_url is None:pytest.skip('Missing test connection')
    engine=create_database_engine(settings,'test')
    schema='bf_test_'+uuid4().hex
    target='bf_test_'+uuid4().hex
    created=False
    try:
        with engine.begin() as c:
            verify_database(c,'test')
            assert not c.scalar(text('SELECT to_regnamespace(:s)'),{'s':target})
            c.exec_driver_sql(f'CREATE SCHEMA "{schema}"')
            created=True
            c.exec_driver_sql('SET LOCAL search_path=pg_catalog,pg_temp')
            for table,expression in [('original',RAW),('emitted',ORIGINAL),('explicit',RESTORED)]:
                c.exec_driver_sql(f'''CREATE TABLE "{schema}".{table} (
                    diameter_m double precision,diameter_kind varchar(20),height_m double precision,
                    CONSTRAINT {NAME} CHECK ({expression}),
                    CONSTRAINT finite_diameter CHECK ({FINITE}),
                    CONSTRAINT has_measurement CHECK (height_m IS NOT NULL OR diameter_m IS NOT NULL))''')
        yield engine,schema,target
    finally:
        if created:
            with engine.begin() as c:
                verify_database(c,'test')
                # Both UUID schemas belong exclusively to this fixture; never public.
                c.exec_driver_sql(f'DROP SCHEMA IF EXISTS "{target}" CASCADE')
                c.exec_driver_sql(f'DROP SCHEMA "{schema}" CASCADE')
        engine.dispose()


def operators(c,tree):
    # Extract only resolved OIDs for test diagnostics; no expression normalization.
    oids=sorted(set(map(int,re.findall(r':opno (\d+)',tree))))
    return [tuple(c.execute(text("""SELECT o.oid::regoperator::text,
        o.oprleft::regtype::text,o.oprright::regtype::text,o.oprresult::regtype::text,
        o.oprcode::regprocedure::text,p.proisstrict
        FROM pg_operator o JOIN pg_proc p ON p.oid=o.oprcode WHERE o.oid=:id"""),{'id':oid}).one()) for oid in oids]


def test_resolved_types_operators_and_casts(focused):
    engine,s,_=focused
    with engine.begin() as c:
        verify_database(c,'test');c.exec_driver_sql('SET LOCAL search_path=pg_catalog,pg_temp')
        old=meta(c,s,'original');new=meta(c,s,'emitted');explicit=meta(c,s,'explicit')
        assert old['expression']==ORIGINAL
        assert new['expression']==explicit['expression']==RESTORED
        assert 'ARRAYCOERCEEXPR' in old['tree'] and 'ARRAYCOERCEEXPR' not in new['tree']
        assert 'ARRAYEXPR' in old['tree'] and 'ARRAYEXPR' in new['tree']
        assert re.findall(r':inputcollid (\d+)',old['tree'])==re.findall(r':inputcollid (\d+)',new['tree'])
        assert ':useOr true' in old['tree'] and ':useOr true' in new['tree']
        assert operators(c,old['tree'])==operators(c,new['tree'])==[('=(text,text)','text','text','boolean','texteq(text,text)',True)]
        assert c.execute(text("""SELECT pg_typeof(ARRAY['stem'::varchar,'canopy'::varchar]::text[])::text,
         pg_typeof(ARRAY[('stem'::varchar)::text,('canopy'::varchar)::text])::text,
         pg_typeof(('stem'::varchar(20))::text)::text""")).one()==('text[]','text[]','text')
        assert c.execute(text("SELECT castmethod,castcontext,castfunc FROM pg_cast WHERE castsource='varchar'::regtype AND casttarget='text'::regtype")).one()==('b','i',0)
        types=c.execute(text("""SELECT attname,format_type(atttypid,atttypmod),attnotnull
         FROM pg_attribute WHERE attrelid=to_regclass(:t) AND attnum>0 ORDER BY attnum"""),{'t':f'"{s}".original'}).all()
        assert types==[('diameter_m','double precision',False),('diameter_kind','character varying(20)',False),('height_m','double precision',False)]


def test_truth_and_effective_check_acceptance(focused):
    engine,s,_=focused
    outcomes=set();membership_outcomes=set();checked=0
    with engine.begin() as c:
        verify_database(c,'test');c.exec_driver_sql('SET LOCAL search_path=pg_catalog,pg_temp')
        cases=[(d,k,1.0) for d in DIAMETERS for k in KINDS]+[(None,None,None),(1.0,'stem',None)]
        for diameter,kind,height in cases:
            params={'d':diameter,'k':kind,'h':height}
            row=c.execute(text(f'''SELECT {ORIGINAL} AS old, {RESTORED} AS restored,
                diameter_kind::text=ANY(ARRAY['stem','canopy']::text[]) AS membership
                FROM (SELECT CAST(:d AS double precision) diameter_m,CAST(:k AS varchar(20)) diameter_kind) v'''),params).one()
            pair=(diameter is None and kind is None) or (diameter is not None and kind in ('stem','canopy'))
            assert row.old is pair and row.restored is pair
            assert row.membership is (None if kind is None else kind in ('stem','canopy'))
            outcomes.add(row.old);membership_outcomes.add(row.membership)
            finite=diameter is None or (math.isfinite(diameter) and diameter>0)
            accepted=pair and finite and (height is not None or diameter is not None)
            for table in ('original','emitted','explicit'):
                try:
                    with c.begin_nested():
                        c.execute(text(f'INSERT INTO "{s}".{table} VALUES(:d,:k,:h)'),params)
                except DBAPIError as error:
                    assert error.orig.sqlstate=='23514' and not accepted
                else:assert accepted
            checked+=1
        assert outcomes=={True,False}  # Complete guard is never UNKNOWN.
        assert membership_outcomes=={True,False,None}
        print(f'CHECK matrix: {checked} synthetic cases x 3 definitions; pair TRUE/FALSE, membership TRUE/FALSE/NULL')


def test_unknown_check_semantics_and_varchar_bound(focused):
    engine,s,_=focused
    with engine.begin() as c:
        verify_database(c,'test')
        c.exec_driver_sql(f'CREATE TABLE "{s}".unknown_control(kind varchar(20) CHECK(kind IN (\'stem\',\'canopy\')))')
        c.exec_driver_sql(f'INSERT INTO "{s}".unknown_control VALUES(NULL)')
        assert c.scalar(text(f'SELECT kind IN (\'stem\',\'canopy\') FROM "{s}".unknown_control')) is None
        for table in ('original','emitted','explicit'):
            for value,state in [('x'*21,'22001'),('stem'+' '*17,'23514')]:
                with pytest.raises(DBAPIError) as error:
                    with c.begin_nested():c.execute(text(f'INSERT INTO "{s}".{table} VALUES(1,:k,1)'),{'k':value})
                # PostgreSQL permits trimming excess trailing spaces to varchar(20),
                # but the remaining spaces still fail the exact kind CHECK.
                assert error.value.orig.sqlstate==state


def test_deparse_then_parse_causes_change_and_next_parse_is_stable(focused):
    engine,s,_=focused
    with engine.begin() as c:
        verify_database(c,'test');c.exec_driver_sql('SET LOCAL search_path=pg_catalog,pg_temp')
        old=meta(c,s,'original')
        assert old['expression']==ORIGINAL and ORIGINAL in old['definition']
        c.exec_driver_sql(f'ALTER TABLE "{s}".original DROP CONSTRAINT {NAME}')
        c.exec_driver_sql(f'ALTER TABLE "{s}".original ADD CONSTRAINT {NAME} '+old['definition'])
        assert meta(c,s,'original')['expression']==RESTORED
        new=meta(c,s,'original')
        c.exec_driver_sql(f'ALTER TABLE "{s}".original DROP CONSTRAINT {NAME}')
        c.exec_driver_sql(f'ALTER TABLE "{s}".original ADD CONSTRAINT {NAME} '+new['definition'])
        assert meta(c,s,'original')['expression']==RESTORED


def test_r1_accepts_only_this_reparsed_constraint(auth_db):
    repository=ResourceRepository(auth_db.repository)
    with auth_db.runtime.begin() as c:repository.verify_schema(c)
    with auth_db.migrator.begin() as c:
        verify_database(c,'test');c.exec_driver_sql('SET LOCAL search_path=pg_catalog,pg_temp')
        old=meta(c,auth_db.schema,'growth_history')
        assert old['expression']==ORIGINAL
        c.exec_driver_sql(f'ALTER TABLE "{auth_db.schema}".growth_history DROP CONSTRAINT {NAME}')
        c.exec_driver_sql(f'ALTER TABLE "{auth_db.schema}".growth_history ADD CONSTRAINT {NAME} '+old['definition'])
        new=meta(c,auth_db.schema,'growth_history')
        assert new['expression']==RESTORED
        for key in ('convalidated','conenforced','condeferrable','condeferred'):assert old[key]==new[key]
        assert c.scalar(text(f'SELECT version_num FROM "{auth_db.schema}".alembic_version'))=='0005_mutation_gateway'
    with auth_db.runtime.begin() as c:
        repository.verify_schema(c)


def test_minimal_real_dump_restore_in_same_test_database(focused,tmp_path):
    engine,s,target=focused
    binary=Path('/usr/lib/postgresql/18/bin')
    env={k:v for k,v in os.environ.items() if not k.startswith('PG')}
    url=engine.url
    env.update(PGHOST=url.host,PGPORT=str(url.port or 5432),PGDATABASE='blueflora_test',PGUSER='blueflora_test',PGPASSWORD=url.password,
               PGPASSFILE='/dev/blueflora-e4-no-password-file',PGSERVICEFILE='/dev/null')
    archive=tmp_path/'synthetic-schema.dump'
    with engine.begin() as c:
        verify_database(c,'test');c.exec_driver_sql('SET LOCAL search_path=pg_catalog,pg_temp')
        old=meta(c,s,'original')
    dump=subprocess.run([str(binary/'pg_dump'),'-w','--schema-only','--format=custom','--schema='+s,'--file='+str(archive)],env=env,capture_output=True)
    assert dump.returncode==0,'Synthetic test pg_dump failed; credentials omitted'
    emitted=subprocess.run([str(binary/'pg_restore'),'--exit-on-error','--single-transaction','--file=-',str(archive)],env=env,capture_output=True,text=True)
    assert emitted.returncode==0,'Synthetic archive SQL generation failed'
    assert ORIGINAL in emitted.stdout  # Dump and SQL still contain the source form.
    sql=emitted.stdout.replace(s,target)  # Only fresh UUID namespace, not expressions.
    restored=subprocess.run([str(binary/'psql'),'-X','-w','-v','ON_ERROR_STOP=1','-q'],input=sql,env=env,capture_output=True,text=True)
    assert restored.returncode==0,'Synthetic psql replay failed; credentials omitted'
    with engine.begin() as c:
        verify_database(c,'test');c.exec_driver_sql('SET LOCAL search_path=pg_catalog,pg_temp')
        new=meta(c,target,'original')
        assert new['expression']==RESTORED
        assert operators(c,old['tree'])==operators(c,new['tree'])
        observation={'server_version':c.scalar(text('SHOW server_version')),'source':old['expression'],'emitted_contains_source':True,'restored':new['expression'],'cause':'parse of emitted explicit array cast'}
    (tmp_path/'roundtrip-observations.json').write_text(json.dumps(observation,indent=2))
    print('Minimal schema-only dump/restore: original -> same emitted SQL -> restored variant; blueflora_test only')


@pytest.mark.parametrize('weakening',['missing','true','null'])
def test_r1_rejects_missing_or_weakened_diameter_check(auth_db,weakening):
    repository=ResourceRepository(auth_db.repository)
    with auth_db.runtime.begin() as c:repository.verify_schema(c)
    with auth_db.migrator.begin() as c:
        verify_database(c,'test')
        c.exec_driver_sql(f'ALTER TABLE "{auth_db.schema}".growth_history DROP CONSTRAINT {NAME}')
        if weakening!='missing':
            clause='TRUE' if weakening=='true' else 'NULL::boolean'
            c.exec_driver_sql(f'ALTER TABLE "{auth_db.schema}".growth_history ADD CONSTRAINT {NAME} CHECK ({clause})')
    with auth_db.runtime.begin() as c:
        with pytest.raises(DatabaseConfigurationError):repository.verify_schema(c)
