"""Upgrade 0003 -> E.4 en un esquema nuevo, bajo transacción externa de pruebas."""
from uuid import uuid4
from datetime import datetime,timezone
import pytest
from alembic import command
from sqlalchemy import text
from app.core.config import Settings
from app.db.connection import create_database_engine,verify_database,set_owner
from test_postgres import migration_config

pytestmark=pytest.mark.postgres

@pytest.fixture
def legacy():
    settings=Settings()
    if settings.test_database_url is None: pytest.skip('Falta conexión de pruebas.')
    engine=create_database_engine(settings,'test')
    with engine.connect() as c:
        tx=c.begin(); schema='bf_test_'+uuid4().hex
        try:
            verify_database(c,'test')
            c.execute(text(f'CREATE SCHEMA "{schema}"'))
            c.execute(text(f'GRANT USAGE ON SCHEMA "{schema}" TO blueflora_api_test'))
            c.execute(text(f'SET LOCAL search_path="{schema}",pg_catalog'))
            command.upgrade(migration_config(c,schema),'0003_resource_permissions')
            yield c,schema
        finally: tx.rollback()
    engine.dispose()


def seed(c,schema):
    s='"'+schema+'"'; o=uuid4(); p=uuid4(); hist=uuid4(); g=uuid4()
    set_owner(c,o)
    c.execute(text(f'INSERT INTO {s}.users(id,email) VALUES(:o,:email)'),{'o':o,'email':str(o)+'@test.invalid'})
    c.execute(text(f"INSERT INTO {s}.gardens(id,owner_id,name) VALUES(:g,:o,'Anterior')"),{'g':g,'o':o})
    c.execute(text(f"INSERT INTO {s}.plants(id,owner_id,garden_id,name,watering_frequency_days,last_watered_at,deleted_at,revision) VALUES(:p,:o,:g,'Conservada',3,:date,:date,9)"),{'p':p,'o':o,'g':g,'date':datetime(2020,1,1,tzinfo=timezone.utc)})
    for ref,link in ((p,p),(hist,None)):
        c.execute(text(f"INSERT INTO {s}.watering_events(id,owner_id,plant_id,plant_ref_id,plant_name_snapshot,occurred_at) VALUES(:e,:o,:link,:ref,'Nombre antiguo',:date)"),{'e':uuid4(),'o':o,'link':link,'ref':ref,'date':datetime(2019,1,1,tzinfo=timezone.utc)})
    return o,p,hist,g


def snapshots(c,schema):
    s='"'+schema+'"'
    return {t:c.execute(text(f'SELECT to_jsonb(t) image FROM {s}.{t} t ORDER BY id')).scalars().all() for t in ('plants','gardens','watering_events','growth_history')}


def test_backfill_force_rls_preserves_all_original_fields_and_no_fake_operations(legacy):
    c,schema=legacy; o,p,hist,g=seed(c,schema); before=snapshots(c,schema)
    command.upgrade(migration_config(c,schema),'head')
    after=snapshots(c,schema)
    for table,originals in before.items():
        for old,new in zip(originals,after[table],strict=True):
            assert all(new[k]==v for k,v in old.items())
    state=c.execute(text(f'SELECT id,state,revision FROM "{schema}".plant_identities ORDER BY state')).all()
    assert {(r.id,r.state,r.revision) for r in state}=={(p,'full',9),(hist,'historical_only',1)}
    assert c.scalar(text(f'SELECT baseline_source FROM "{schema}".plants'))=='legacy_snapshot'
    for table in ('sync_operations','sync_change_groups'):
        assert c.scalar(text(f'SELECT count(*) FROM "{schema}".{table}'))==0
    assert c.scalar(text("SELECT current_setting('blueflora.owner_id')"))==str(o)
    assert c.scalar(text("SELECT current_setting('blueflora.auth_internal',true)")) in ('',None)


@pytest.mark.parametrize('collision',['historical_cross_owner','full_cross_owner'])
def test_collision_blocks_and_rolls_back_whole_upgrade(legacy,collision):
    c,schema=legacy; first,p,hist,g=seed(c,schema); second=uuid4(); set_owner(c,second)
    c.execute(text(f'INSERT INTO "{schema}".users(id,email) VALUES(:o,:email)'),{'o':second,'email':str(second)+'@test.invalid'})
    ref=hist if collision=='historical_cross_owner' else p
    c.execute(text(f"INSERT INTO \"{schema}\".watering_events(id,owner_id,plant_ref_id,plant_name_snapshot,occurred_at) VALUES(:e,:o,:ref,'Colisión',now())"),{'e':uuid4(),'o':second,'ref':ref})
    with pytest.raises(RuntimeError,match='colisión'):
        with c.begin_nested(): command.upgrade(migration_config(c,schema),'head')
    assert c.scalar(text(f'SELECT version_num FROM "{schema}".alembic_version'))=='0003_resource_permissions'
    assert c.scalar(text('SELECT to_regclass(:t)'),{'t':'"'+schema+'".plant_identities'}) is None
    assert c.scalar(text(f'SELECT count(*) FROM "{schema}".watering_events'))==1


def test_late_failure_rolls_back_both_migrations_grants_and_data(legacy):
    c,schema=legacy; o,p,hist,g=seed(c,schema); before=snapshots(c,schema)
    with pytest.raises(RuntimeError,match='corte sintético'):
        with c.begin_nested():
            command.upgrade(migration_config(c,schema),'head')
            raise RuntimeError('corte sintético antes del COMMIT externo')
    assert c.scalar(text(f'SELECT version_num FROM "{schema}".alembic_version'))=='0003_resource_permissions'
    assert snapshots(c,schema)==before
    assert c.scalar(text("SELECT has_column_privilege('blueflora_api_test',:t,'name','UPDATE')"),{'t':'"'+schema+'".plants'})
    assert c.scalar(text('SELECT to_regprocedure(:t)'),{'t':'"'+schema+'".resource_apply(uuid,text)'}) is None


def test_original_migrations_still_reverse_only_before_e4(legacy):
    c,schema=legacy
    command.downgrade(migration_config(c,schema),'base')
    assert c.scalar(text(f'SELECT count(*) FROM "{schema}".alembic_version'))==0
    command.upgrade(migration_config(c,schema),'0003_resource_permissions')
    assert c.scalar(text(f'SELECT version_num FROM "{schema}".alembic_version'))=='0003_resource_permissions'

@pytest.mark.parametrize('size,allowed',[(64000,True),(65536,False)])
def test_backfill_measures_complete_group_without_truncation(legacy,size,allowed):
    c,schema=legacy; owner,p,hist,g=seed(c,schema)
    c.execute(text(f'UPDATE "{schema}".gardens SET description=:value'),{'value':'a'*size})
    if allowed:
        command.upgrade(migration_config(c,schema),'head')
        assert c.scalar(text(f'SELECT length(description) FROM "{schema}".gardens'))==size
    else:
        with pytest.raises(RuntimeError,match='fuera de límite'):
            with c.begin_nested(): command.upgrade(migration_config(c,schema),'head')
        assert c.scalar(text(f'SELECT version_num FROM "{schema}".alembic_version'))=='0003_resource_permissions'
        assert c.scalar(text(f'SELECT length(description) FROM "{schema}".gardens'))==size
