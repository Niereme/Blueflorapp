"""R1: exact catalog contract, technical NULL path and fail-closed readiness.

Only existing test roles and disposable schemas from auth_db are used.
"""
from uuid import uuid4
import shutil

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from alembic import command
from alembic.config import Config
from app.core.config import BACKEND_ROOT
from app.db.connection import DatabaseConfigurationError, verify_api, verify_database, set_owner
from app.modules.common.repository import ResourceRepository
from app.modules.common.mutation import canonical
from test_auth import auth_db, auth_client, register, login, bearer

pytestmark=pytest.mark.postgres


def probe(db,c):
    return c.scalar(text(f'SELECT "{db.schema}".resource_apply(NULL,NULL)'))


def context(c):
    return tuple(c.execute(text("""SELECT current_setting('blueflora.owner_id',true),
        current_setting('blueflora.auth_internal',true),current_setting('search_path'),
        current_setting('TimeZone'),current_setting('transaction_read_only'),current_user""")).one())


def counts(db,owner=None):
    # Synthetic fixture only. Return counts, never rows or payloads.
    with db.migrator.begin() as c:
        c.execute(text("SELECT set_config('blueflora.auth_internal','on',true)"))
        if owner: set_owner(c,owner)
        names=c.execute(text("SELECT relname FROM pg_class WHERE relnamespace=to_regnamespace(:s) AND relkind='r' ORDER BY relname"),{'s':db.schema}).scalars().all()
        return {n:c.scalar(text(f'SELECT count(*) FROM "{db.schema}"."{n}"')) for n in names}


@pytest.mark.parametrize('owner',[None,'','11111111-1111-4111-8111-111111111111','not-a-uuid'])
def test_technical_probe_read_only_exact_context_and_no_rows(auth_db,owner):
    before=counts(auth_db)
    with auth_db.runtime.connect() as c:
        c.exec_driver_sql('SET TRANSACTION READ ONLY')
        verify_api(c,'test')
        if owner is not None:
            c.execute(text("SELECT set_config('blueflora.owner_id',:o,true)"),{'o':owner})
        c.execute(text("SELECT set_config('blueflora.auth_internal','off',true)"))
        c.exec_driver_sql("SET LOCAL TimeZone='America/Mexico_City'")
        c.exec_driver_sql('SET LOCAL search_path=pg_catalog')
        original=context(c)
        assert probe(auth_db,c)=={'ready':True,'manifest':'e4-r1-pg18'}
        ResourceRepository(auth_db.repository).verify_schema(c)
        assert context(c)==original
        c.commit()  # READ ONLY success also proves the result did not rely on rollback.
    assert counts(auth_db)==before


@pytest.mark.parametrize('owner',[None,'11111111-1111-4111-8111-111111111111'])
@pytest.mark.parametrize('partial',['id','request'])
def test_partial_null_rejected_without_effects(auth_db,owner,partial):
    before=counts(auth_db)
    with auth_db.runtime.begin() as c:
        c.exec_driver_sql('SET TRANSACTION READ ONLY')
        verify_api(c,'test')
        if owner: set_owner(c,owner)
        original=context(c)
        with pytest.raises(DBAPIError) as error:
            with c.begin_nested():
                c.execute(text(f'SELECT "{auth_db.schema}".resource_apply(:id,:request)'),
                          {'id':uuid4() if partial=='id' else None,'request':'{}' if partial=='request' else None})
        assert error.value.orig.sqlstate=='22023'
        assert context(c)==original
    assert counts(auth_db)==before


@pytest.mark.anyio
async def test_probe_with_real_owner_does_not_create_state_or_bypass_auth(auth_db,auth_client):
    await register(auth_client)
    tokens=await login(auth_client)
    owner=(await auth_client.get('/api/v1/me',headers=bearer(tokens))).json()['id']
    before=counts(auth_db,owner)
    assert before['sync_owner_state']==before['sync_operations']==before['sync_change_groups']==0
    with auth_db.runtime.begin() as c:
        c.exec_driver_sql('SET TRANSACTION READ ONLY')
        verify_api(c,'test')
        set_owner(c,owner)
        original=context(c)
        assert probe(auth_db,c)=={'ready':True,'manifest':'e4-r1-pg18'}
        assert context(c)==original
    operation=uuid4()
    response=await auth_client.post('/api/v1/gardens',json={'name':'Synthetic'},headers={'Idempotency-Key':str(operation)})
    assert response.status_code==401
    with auth_db.runtime.begin() as c:
        verify_api(c,'test')
        assert probe(auth_db,c)['ready']
        with pytest.raises(DBAPIError) as error:
            with c.begin_nested():
                c.execute(text(f'SELECT "{auth_db.schema}".resource_apply(:id,:request)'),
                          {'id':operation,'request':canonical(operation,'garden.create',None,{'name':'Synthetic'})})
        assert error.value.orig.sqlstate=='42501'
    assert counts(auth_db,owner)==before


DRIFTS={
 'policy_using':'ALTER POLICY owner_isolation ON {s}.plants USING (true)',
 'policy_check':'ALTER POLICY owner_isolation ON {s}.plants WITH CHECK (true)',
 'policy_role':'ALTER POLICY owner_isolation ON {s}.plants TO blueflora_api_test',
 'policy_command':'DROP POLICY owner_isolation ON {s}.plants; CREATE POLICY owner_isolation ON {s}.plants FOR SELECT USING (owner_id=nullif(current_setting(\'blueflora.owner_id\',true),\'\')::uuid)',
 'force':'ALTER TABLE {s}.plants NO FORCE ROW LEVEL SECURITY',
 'enable':'ALTER TABLE {s}.plants DISABLE ROW LEVEL SECURITY',
 'unique':'ALTER TABLE {s}.sync_change_groups DROP CONSTRAINT uq_group_operation',
 'column_permission':'GRANT UPDATE(name) ON {s}.plants TO blueflora_api_test',
 'column_public':'GRANT SELECT(response_body) ON {s}.sync_operations TO PUBLIC',
 'effective_permission':'GRANT SELECT ON {s}.sync_operations TO blueflora_api_test',
 'public_permission':'GRANT INSERT ON {s}.gardens TO PUBLIC',
 'trigger':'ALTER TABLE {s}.sync_operations DISABLE TRIGGER immutable',
 'trigger_function':"CREATE OR REPLACE FUNCTION {s}.reject_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $$ BEGIN RETURN NEW; END $$",
 'gateway_definer':'ALTER FUNCTION {s}.resource_apply(uuid,text) SECURITY INVOKER',
 'gateway_path':"ALTER FUNCTION {s}.resource_apply(uuid,text) SET search_path=pg_catalog",
 'column_type':'ALTER TABLE {s}.sync_owner_state ALTER COLUMN last_sequence TYPE numeric',
 'column_null':'ALTER TABLE {s}.gardens ALTER COLUMN updated_at DROP NOT NULL',
 'fk':None,
}


@pytest.mark.parametrize('drift',DRIFTS)
@pytest.mark.anyio
async def test_head_retained_but_capability_drift_fails_closed(auth_db,auth_client,drift):
    repository=ResourceRepository(auth_db.repository)
    with auth_db.runtime.begin() as c:
        verify_api(c,'test')
        repository.verify_schema(c)
    with auth_db.migrator.begin() as c:
        verify_database(c,'test')
        s='"'+auth_db.schema+'"'
        if drift=='fk':
            constraint=c.scalar(text("""SELECT conname FROM pg_constraint WHERE conrelid=to_regclass(:table)
                AND confrelid=to_regclass(:ref) AND contype='f'"""),{'table':s+'.plants','ref':s+'.gardens'})
            assert constraint
            c.exec_driver_sql(f'ALTER TABLE {s}.plants DROP CONSTRAINT "{constraint}"')
        else:
            c.exec_driver_sql(DRIFTS[drift].format(s=s),execution_options={'no_parameters':True})
        assert c.scalar(text(f'SELECT version_num FROM {s}.alembic_version'))=='0005_mutation_gateway'
    with auth_db.runtime.begin() as c:
        verify_api(c,'test')
        with pytest.raises(DatabaseConfigurationError):
            repository.verify_schema(c)
    with pytest.raises(DatabaseConfigurationError):
        async with auth_db.app.router.lifespan_context(auth_db.app): pass
    assert (await auth_client.get('/health/live')).status_code==200


def test_migration_artifacts_from_complete_clean_copy(auth_db,tmp_path,monkeypatch):
    # No cwd/absolute external sidecar dependency; run all migrations from copied sources.
    copy=tmp_path/'backend'
    shutil.copytree(BACKEND_ROOT/'migrations',copy/'migrations',ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copy2(BACKEND_ROOT/'alembic.ini',copy/'alembic.ini')
    schema=f'bf_test_{uuid4().hex}'
    monkeypatch.chdir(tmp_path)
    config=Config(str(copy/'alembic.ini'))
    config.set_main_option('script_location',str(copy/'migrations'))
    with auth_db.migrator.connect() as c:
        transaction=c.begin()
        verify_database(c,'test')
        c.exec_driver_sql(f'CREATE SCHEMA "{schema}"')
        try:
            c.exec_driver_sql(f'GRANT USAGE ON SCHEMA "{schema}" TO blueflora_api_test')
            c.exec_driver_sql(f'SET LOCAL search_path="{schema}",pg_catalog')
            config.attributes.update(connection=c,test_schema=schema)
            command.upgrade(config,'head')
            c.exec_driver_sql('SET LOCAL search_path=pg_catalog,pg_temp')
            assert c.scalar(text(f'SELECT "{schema}".resource_apply(NULL,NULL)'))['manifest']=='e4-r1-pg18'
        finally:
            transaction.rollback()
