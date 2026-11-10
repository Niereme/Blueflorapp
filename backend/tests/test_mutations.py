"""E.4: protocolo real contra API-test; sin autoheaders en las pruebas de contrato."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
import struct
import threading
import time
from uuid import UUID,uuid4
import pytest
import rfc8785
from fastapi import HTTPException
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from app.modules.common.mutation import canonical
from app.modules.common.repository import ResourceRepository
from app.db.connection import set_owner,verify_api
from test_auth import auth_db,auth_client,register,login,bearer
from test_resources import actors,plant,garden,now


# RFC8785 Appendix B, hexadecimal binary64 -> serialization; no floating literal approximation.
VECTORS=[
 ('0000000000000000','0'),('8000000000000000','0'),('0000000000000001','5e-324'),('8000000000000001','-5e-324'),
 ('7fefffffffffffff','1.7976931348623157e+308'),('ffefffffffffffff','-1.7976931348623157e+308'),
 ('4340000000000000','9007199254740992'),('c340000000000000','-9007199254740992'),('4430000000000000','295147905179352830000'),
 ('44b52d02c7e14af5','9.999999999999997e+22'),('44b52d02c7e14af6','1e+23'),('44b52d02c7e14af7','1.0000000000000001e+23'),
 ('444b1ae4d6e2ef4e','999999999999999700000'),('444b1ae4d6e2ef4f','999999999999999900000'),('444b1ae4d6e2ef50','1e+21'),
 ('3eb0c6f7a0b5ed8c','9.999999999999997e-7'),('3eb0c6f7a0b5ed8d','0.000001'),
 ('41b3de4355555553','333333333.3333332'),('41b3de4355555554','333333333.33333325'),('41b3de4355555555','333333333.3333333'),
 ('41b3de4355555556','333333333.3333334'),('41b3de4355555557','333333333.33333343'),
 ('becbf647612f3696','-0.0000033333333333333333'),('43143ff3c1cb0959','1424953923781206.2')]

@pytest.mark.parametrize('bits,expected',VECTORS)
def test_rfc8785_appendix_b(bits,expected):
    value=struct.unpack('>d',bytes.fromhex(bits))[0]
    assert rfc8785.dumps(value)==expected.encode()

@pytest.mark.parametrize('value',[float('nan'),float('inf'),float('-inf'),'\ud800',{1:'x'},2**64])
def test_jcs_invalid_values(value):
    with pytest.raises(rfc8785.CanonicalizationError): rfc8785.dumps(value)

def test_jcs_utf16_controls_preserved_unicode_and_absence():
    values={'\ue000':1,'\U0001f600':2,'a':'\x00\n"\\'}
    assert rfc8785.dumps(values)==b'{"a":"\\u0000\\n\\"\\\\","\xf0\x9f\x98\x80":2,"\xee\x80\x80":1}'
    assert rfc8785.dumps({'b':1.0,'a':None})==b'{"a":null,"b":1}'
    assert rfc8785.dumps({})!=rfc8785.dumps({'a':None})
    assert rfc8785.dumps('é')!=rfc8785.dumps('e\u0301')


def headers(actor,op=None,match=None):
    h={**actor,'Idempotency-Key':str(op or uuid4())}
    if match is not None: h['If-Match']=match
    return h

async def owner_id(client,actor): return (await client.get('/api/v1/me',headers=actor)).json()['id']

def rows(db,owner,sql,params=None):
    with db.migrator.begin() as c:
        set_owner(c,owner)
        return c.execute(text(sql.replace('SCHEMA','"'+db.schema+'"')),params or {}).mappings().all()

def counts(db,owner):
    return {t:rows(db,owner,f'SELECT count(*) n FROM SCHEMA.{t}')[0]['n'] for t in ('sync_operations','sync_change_groups','plants','watering_events')}

@pytest.mark.postgres
@pytest.mark.anyio
async def test_replay_original_bytes_headers_after_edit_delete_and_invalid_session(actors,auth_client,auth_db):
    op=uuid4(); h=headers(actors.a,op); body={'name':'Original','watering_frequency_days':2}
    first=await auth_client.post('/api/v1/plants',json=body,headers=h)
    assert first.status_code==201
    path=first.headers['location']
    get=await auth_client.get(path,headers=actors.a)
    assert get.content==first.content and get.headers['etag']==first.headers['etag']
    edit=await auth_client.patch(path,json={'name':'Nueva'},headers=headers(actors.a,match=first.headers['etag']))
    assert edit.status_code==200 and edit.headers['etag']!=first.headers['etag']
    deleted=await auth_client.delete(path,headers=headers(actors.a,match=edit.headers['etag']))
    assert deleted.status_code==204 and deleted.content==b''
    replay=await auth_client.post('/api/v1/plants',json=body,headers=h)
    assert replay.content==first.content and replay.status_code==201
    assert all(replay.headers[k]==first.headers[k] for k in ('location','etag','content-type'))
    reused=await auth_client.post('/api/v1/plants',json={**body,'name':'Otra'},headers=h)
    assert reused.status_code==409 and reused.json()['detail']['code']=='operation_id_reused'
    o=await owner_id(auth_client,actors.a)
    assert counts(auth_db,o)['sync_operations']==3
    await auth_client.post('/api/v1/auth/logout',headers=actors.a)
    assert (await auth_client.post('/api/v1/plants',json=body,headers=h)).status_code==401

@pytest.mark.postgres
@pytest.mark.anyio
async def test_terminal_before_cas_noop_and_nondurable_headers(actors,auth_client,auth_db):
    p=await plant(actors); path='/api/v1/plants/'+p['id']; o=await owner_id(auth_client,actors.a)
    tag=(await auth_client.get(path,headers=actors.a)).headers['etag']
    before=counts(auth_db,o)
    for h,expected in [(actors.a,422),(headers(actors.a),428),(headers(actors.a,match='*'),422)]:
        assert (await auth_client.patch(path,json={'name':'x'},headers=h)).status_code==expected
    assert counts(auth_db,o)==before
    noop=await auth_client.patch(path,json={'name':p['name']},headers=headers(actors.a,match=tag))
    assert noop.status_code==200 and noop.headers['etag']==tag
    assert counts(auth_db,o)['sync_change_groups']==before['sync_change_groups']
    badtag=tag.replace('-r1','-r2'); rejected_headers=headers(actors.a,match=badtag)
    rejected=await auth_client.patch(path,json={'name':'Cambio'},headers=rejected_headers)
    assert rejected.status_code==412
    edited=await auth_client.patch(path,json={'name':'Real'},headers=headers(actors.a,match=tag))
    assert edited.status_code==200
    replay=await auth_client.patch(path,json={'name':'Cambio'},headers=rejected_headers)
    assert replay.content==rejected.content and replay.status_code==412  # r2 is now current, still rejection.
    corrected=await auth_client.patch(path,json={'name':'Cambio'},headers=headers(actors.a,match=badtag))
    assert corrected.status_code==200
    record=rows(auth_db,o,'SELECT committed_sequence,terminal_status FROM SCHEMA.sync_operations WHERE operation_id=:id',{'id':rejected_headers['Idempotency-Key']})[0]
    assert record['committed_sequence'] is None and record['terminal_status']=='conflict'

@pytest.mark.postgres
@pytest.mark.anyio
async def test_intention_null_omission_uuid_datetime_and_sql_hash(actors,auth_client,auth_db):
    op=uuid4(); h=headers(actors.a,op); o=await owner_id(auth_client,actors.a)
    body={'name':'Planta','watering_frequency_days':1,'id':str(uuid4()).upper(),'last_watered_at':'2020-01-01T12:00:00-06:00'}
    first=await auth_client.post('/api/v1/plants',json=body,headers=h)
    assert first.status_code==201
    equivalent={**body,'id':body['id'].lower(),'last_watered_at':'2020-01-01T18:00:00.000000Z'}
    assert (await auth_client.post('/api/v1/plants',json=equivalent,headers=h)).content==first.content
    changed=await auth_client.post('/api/v1/plants',json={**equivalent,'species_label':None},headers=h)
    assert changed.status_code==409
    record=rows(auth_db,o,"SELECT canonical_request,fingerprint,sha256(convert_to(canonical_request,'UTF8')) sql_hash FROM SCHEMA.sync_operations WHERE operation_id=:id",{'id':op})[0]
    raw=record['canonical_request'].encode()
    assert bytes(record['fingerprint'])==bytes(record['sql_hash'])==hashlib.sha256(raw).digest()
    assert rfc8785.dumps(json.loads(raw))==raw

@pytest.mark.postgres
@pytest.mark.anyio
async def test_input_limits_duplicate_unicode_nonfinite_before_receipt(actors,auth_client,auth_db):
    o=await owner_id(auth_client,actors.a); before=counts(auth_db,o)
    samples=[('{"name":"a","name":"b","watering_frequency_days":1}',422),
       ('{"name":"\\ud800","watering_frequency_days":1}',422),
       ('{"name":"a","watering_frequency_days":true}',422),
       ('{"name":"a","watering_frequency_days":1,"initial_height_m":1e999}',422),
       ('['*17+'0'+']'*17,422),('x'*65537,413)]
    for raw,status in samples:
        response=await auth_client.post('/api/v1/plants',content=raw,headers={**headers(actors.a),'Content-Type':'application/json'})
        assert response.status_code==status
    assert counts(auth_db,o)==before
    # Chunked input cannot evade the byte limit.
    async def stream():
        for _ in range(70): yield b' '*1024
    assert (await auth_client.post('/api/v1/plants',content=stream(),headers={**headers(actors.a),'Content-Type':'application/json'})).status_code==413

@pytest.mark.postgres
@pytest.mark.anyio
async def test_etag_covers_each_individual_representation_and_snapshots(actors,auth_client,auth_db):
    g=await garden(actors); p=await plant(actors,garden_id=g['id'],initial_height_m=1.0); path='/api/v1/plants/'+p['id']
    before=await auth_client.get(path,headers=actors.a)
    event=await auth_client.post(path+'/watering-events',json={'occurred_at':now()},headers=headers(actors.a))
    assert event.status_code==201
    after=await auth_client.get(path,headers=actors.a)
    assert after.content!=before.content and after.headers['etag']!=before.headers['etag']
    history=await auth_client.get(event.headers['location'],headers=actors.a)
    assert history.content==event.content and history.headers['etag']==event.headers['etag']
    await actors.client.patch('/api/v1/gardens/'+g['id'],json={'name':'Jardín nuevo'},headers=actors.a)
    unchanged=await auth_client.get(path,headers=actors.a)
    assert unchanged.content==after.content and unchanged.headers['etag']==after.headers['etag']
    await actors.client.patch(path,json={'name':'Renombrada'},headers=actors.a)
    await actors.client.delete(path,headers=actors.a)
    retained=await auth_client.get(event.headers['location'],headers=actors.a)
    assert retained.content==history.content and retained.headers['etag']==history.headers['etag']
    assert retained.json()['plant_name_snapshot']=='Lavanda'

@pytest.mark.postgres
@pytest.mark.anyio
async def test_archive_relationships_and_replay_fact_after_deletion(actors,auth_client):
    g=await garden(actors); p=await plant(actors,garden_id=g['id']); path='/api/v1/plants/'+p['id']
    op=uuid4(); h=headers(actors.a,op); body={'height_m':1.0,'measured_at':now()}
    fact=await auth_client.post(path+'/growth-history',json=body,headers=h)
    assert fact.status_code==201
    await actors.client.delete('/api/v1/gardens/'+g['id'],headers=actors.a)
    edited=await actors.client.patch(path,json={'name':'Guardada','garden_id':g['id']},headers=actors.a)
    assert edited.status_code==200 and edited.json()['garden_id']==g['id']
    blocked=await auth_client.post('/api/v1/plants',json={'name':'Nueva','watering_frequency_days':1,'garden_id':g['id']},headers=headers(actors.a))
    assert blocked.status_code==409
    await actors.client.delete(path,headers=actors.a)
    replay=await auth_client.post(path+'/growth-history',json=body,headers=h)
    assert replay.content==fact.content and replay.status_code==201
    assert (await auth_client.post(path+'/growth-history',json=body,headers=headers(actors.a))).status_code==404

@pytest.mark.postgres
@pytest.mark.anyio
async def test_lost_response_commit_and_byte_comparison(actors,auth_client,auth_db):
    op=uuid4(); raw=canonical(op,'garden.create',None,{'name':'Durable'})
    repository=ResourceRepository(auth_db.repository); access=actors.a['Authorization'].split()[1]
    # Simulate application losing the result after the actual COMMIT.
    repository.apply(access,op,raw)
    recovered=repository.apply(access,op,raw)
    assert recovered['status']==201
    o=await owner_id(auth_client,actors.a)
    assert rows(auth_db,o,'SELECT last_sequence FROM SCHEMA.sync_owner_state')[0]['last_sequence']==1
    # Equal semantic JSON with different bytes must not be accepted by SQL as replay.
    with auth_db.runtime.begin() as c:
        set_owner(c,o)
        different=c.scalar(text(f'SELECT "{auth_db.schema}".resource_apply(:op,:raw)'),{'op':op,'raw':json.dumps(json.loads(raw),indent=1)})
    assert different['status']==409

@pytest.mark.postgres
@pytest.mark.anyio
@pytest.mark.parametrize('table',['plants','sync_change_groups','sync_operations'])
async def test_failure_at_each_stage_rolls_back_everything(actors,auth_client,auth_db,table,monkeypatch):
    o=await owner_id(auth_client,actors.a); before=counts(auth_db,o); op=uuid4()
    # First attest the real contract. The synthetic extra trigger intentionally
    # violates R1's exact trigger manifest; this atomicity test must reach SQL,
    # rather than pass because readiness rejected its injected trigger.
    with auth_db.runtime.begin() as c:
        ResourceRepository(auth_db.repository).verify_schema(c)
    # Fault injection exists ONLY in this test schema; no production bypass hook.
    with auth_db.migrator.begin() as c:
        c.execute(text(f'''CREATE FUNCTION "{auth_db.schema}".fail_test_insert() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic failure' USING ERRCODE='23514'; END $$'''))
        c.execute(text(f'CREATE TRIGGER fail_test_insert BEFORE INSERT ON "{auth_db.schema}".{table} FOR EACH ROW EXECUTE FUNCTION "{auth_db.schema}".fail_test_insert()'))
    observed=[]
    original_apply=ResourceRepository.apply
    def observe_sql_failure(self,*args):
        try:
            return original_apply(self,*args)
        except DBAPIError as exc:
            observed.append(exc.orig.sqlstate)
            raise
    with monkeypatch.context() as patch:
        # Only this faulted request bypasses metadata attestation; authentication,
        # gateway, transaction, CAS and rollback remain real and unpatched.
        patch.setattr(ResourceRepository,'verify_schema',lambda self,c:None)
        patch.setattr(ResourceRepository,'apply',observe_sql_failure)
        response=await auth_client.post('/api/v1/plants',json={'name':'Fallida','watering_frequency_days':1},headers=headers(actors.a,op))
    assert observed==['23514']
    assert response.status_code==503 and counts(auth_db,o)==before
    with auth_db.migrator.begin() as c: c.execute(text(f'DROP TRIGGER fail_test_insert ON "{auth_db.schema}".{table}'))
    assert (await auth_client.post('/api/v1/plants',json={'name':'Fallida','watering_frequency_days':1},headers=headers(actors.a,op))).status_code==201

@pytest.mark.postgres
@pytest.mark.anyio
async def test_runtime_acl_public_immutable_and_schema_failure(actors,auth_client,auth_db):
    p=await plant(actors); o=await owner_id(auth_client,actors.a); s='"'+auth_db.schema+'"'
    path='/api/v1/plants/'+p['id']
    assert (await auth_client.post(path+'/watering-events',json={'occurred_at':now()},headers=headers(actors.a))).status_code==201
    assert (await auth_client.post(path+'/growth-history',json={'measured_at':now(),'height_m':1},headers=headers(actors.a))).status_code==201
    with auth_db.runtime.begin() as c:
        verify_api(c,'test'); set_owner(c,o)
        for query in [f"UPDATE {s}.plants SET name='Bypass'",f'DELETE FROM {s}.gardens',f'INSERT INTO {s}.sync_operations(owner_id) VALUES(:o)',f'SELECT * FROM {s}.sync_operations',f'SELECT {s}.reject_immutable()']:
            with pytest.raises(DBAPIError):
                with c.begin_nested(): c.execute(text(query),{'o':o})
    with auth_db.migrator.begin() as c:
        set_owner(c,o)
        for table in ('sync_operations','sync_change_groups','watering_events','growth_history'):
            for verb in (f'UPDATE {s}.{table} SET owner_id=owner_id',f'DELETE FROM {s}.{table}'):
                with pytest.raises(DBAPIError):
                    with c.begin_nested(): c.execute(text(verb))
        assert not c.scalar(text("SELECT EXISTS(SELECT 1 FROM pg_class t JOIN pg_namespace n ON n.oid=t.relnamespace, LATERAL aclexplode(coalesce(t.relacl,acldefault('r',t.relowner))) a WHERE n.nspname=:schema AND a.grantee=0)"),{'schema':auth_db.schema})
        c.execute(text(f"UPDATE {s}.alembic_version SET version_num='0003_resource_permissions'"))
    assert (await auth_client.get('/api/v1/plants',headers=actors.a)).status_code==503
    assert (await auth_client.get('/health/live')).status_code==200

@pytest.mark.postgres
@pytest.mark.anyio
@pytest.mark.parametrize('rollback_first',[False,True])
async def test_owner_commit_order_and_rollback_without_sequence_hole(actors,auth_client,auth_db,rollback_first):
    o=await owner_id(auth_client,actors.a); access=actors.a['Authorization'].split()[1]
    first=auth_db.runtime.connect(); tx=first.begin(); set_owner(first,o)
    op1=uuid4(); op2=uuid4()
    f1=canonical(op1,'garden.create',None,{'name':'Primero'}); f2=canonical(op2,'garden.create',None,{'name':'Segundo'})
    first.scalar(text(f'SELECT "{auth_db.schema}".resource_apply(:op,:raw)'),{'op':op1,'raw':f1})
    first.execute(text("SET LOCAL idle_in_transaction_session_timeout='8s'"))
    first_pid=first.scalar(text('SELECT pg_backend_pid()'))
    started=threading.Event(); pid=[]
    def second():
        with auth_db.runtime.begin() as c:
            verify_api(c,'test'); set_owner(c,o); pid.append(c.scalar(text('SELECT pg_backend_pid()'))); started.set()
            return c.scalar(text(f'SELECT "{auth_db.schema}".resource_apply(:op,:raw)'),{'op':op2,'raw':f2})
    try:
        with ThreadPoolExecutor(max_workers=1) as executor:
            future=executor.submit(second); assert started.wait(3)
            with auth_db.migrator.connect() as probe:
                for _ in range(200):
                    blocking=probe.scalar(text('SELECT pg_blocking_pids(:pid)'),{'pid':pid[0]})
                    if first_pid in blocking: break
                    time.sleep(.01)
                assert first_pid in blocking and not future.done()
            if rollback_first: tx.rollback()
            else: tx.commit()
            assert future.result(timeout=5)['status']==201
    finally:
        if tx.is_active: tx.rollback()
        first.close()
    seq=rows(auth_db,o,'SELECT sequence FROM SCHEMA.sync_change_groups ORDER BY sequence')
    assert [r['sequence'] for r in seq]==([1] if rollback_first else [1,2])

@pytest.mark.postgres
def test_all_rfc_vector_utf8_hashes_match_sql(auth_db):
    with auth_db.runtime.connect() as c:
        verify_api(c,'test')
        for bits,expected in VECTORS:
            raw=rfc8785.dumps(struct.unpack('>d',bytes.fromhex(bits))[0])
            sql=c.scalar(text("SELECT sha256(convert_to(:raw,'UTF8'))"),{'raw':raw.decode()})
            assert bytes(sql)==hashlib.sha256(raw).digest()
        raw=rfc8785.dumps({'é':'\U0001f600','\ue000':None,'\U0001f600':'e\u0301'})
        assert bytes(c.scalar(text("SELECT sha256(convert_to(:raw,'UTF8'))"),{'raw':raw.decode()}))==hashlib.sha256(raw).digest()

@pytest.mark.postgres
@pytest.mark.anyio
async def test_future_terminal_durable_and_bigint_counter_rollback(actors,auth_client,auth_db):
    p=await plant(actors); path='/api/v1/plants/'+p['id']; o=await owner_id(auth_client,actors.a)
    h=headers(actors.a); body={'occurred_at':'2999-01-01T00:00:00Z'}
    first=await auth_client.post(path+'/watering-events',json=body,headers=h)
    again=await auth_client.post(path+'/watering-events',json=body,headers=h)
    assert first.status_code==again.status_code==422 and first.content==again.content
    assert first.json()['detail']['code']=='timestamp_in_future' and 'server_time' in first.json()
    with auth_db.migrator.begin() as c:
        set_owner(c,o)
        c.execute(text(f'UPDATE "{auth_db.schema}".sync_owner_state SET last_sequence=9223372036854775807'))
    before=counts(auth_db,o)
    failed=await auth_client.post(path+'/watering-events',json={'occurred_at':now()},headers=headers(actors.a))
    assert failed.status_code==503 and counts(auth_db,o)==before
    assert (await auth_client.get(path,headers=actors.a)).json()['last_watered_at'] is None

@pytest.mark.postgres
@pytest.mark.anyio
async def test_readiness_on_startup_and_broken_capability(actors,auth_client,auth_db):
    from app.db.connection import DatabaseConfigurationError
    async with auth_db.app.router.lifespan_context(auth_db.app): pass
    with auth_db.migrator.begin() as c:
        c.execute(text(f'ALTER TABLE "{auth_db.schema}".sync_operations DISABLE TRIGGER immutable'))
    with pytest.raises(DatabaseConfigurationError):
        async with auth_db.app.router.lifespan_context(auth_db.app): pass
    assert (await auth_client.get('/api/v1/plants',headers=actors.a)).status_code==503

@pytest.mark.postgres
@pytest.mark.anyio
async def test_hash_collision_still_compares_original_bytes(actors,auth_client,auth_db):
    op=uuid4(); raw=canonical(op,'garden.create',None,{'name':'Original'}); other=canonical(op,'garden.create',None,{'name':'Otra'})
    access=actors.a['Authorization'].split()[1]; repository=ResourceRepository(auth_db.repository)
    repository.apply(access,op,raw); o=await owner_id(auth_client,actors.a)
    # Solo en el esquema efímero: simular una colisión de SHA sin reemplazar bytes.
    with auth_db.migrator.begin() as c:
        set_owner(c,o)
        c.execute(text(f'ALTER TABLE "{auth_db.schema}".sync_operations DISABLE TRIGGER immutable'))
        c.execute(text(f'UPDATE "{auth_db.schema}".sync_operations SET fingerprint=sha256(convert_to(:raw,\'UTF8\')) WHERE operation_id=:op'),{'raw':other,'op':op})
        c.execute(text(f'ALTER TABLE "{auth_db.schema}".sync_operations ENABLE TRIGGER immutable'))
    assert repository.apply(access,op,other)['status']==409

@pytest.mark.postgres
@pytest.mark.anyio
async def test_other_owner_does_not_wait_for_uncommitted_owner(actors,auth_client,auth_db):
    a=await owner_id(auth_client,actors.a); b=await owner_id(auth_client,actors.b)
    c=auth_db.runtime.connect(); tx=c.begin(); set_owner(c,a)
    op=uuid4(); raw=canonical(op,'garden.create',None,{'name':'Privado'})
    try:
        original=c.scalar(text(f'SELECT "{auth_db.schema}".resource_apply(:op,:raw)'),{'op':op,'raw':raw})
        access=actors.b['Authorization'].split()[1]; second=uuid4()
        result=ResourceRepository(auth_db.repository).apply(access,second,canonical(second,'garden.create',None,{'name':'Independiente'}))
        assert result['status']==201
        assert rows(auth_db,b,'SELECT last_sequence FROM SCHEMA.sync_owner_state')[0]['last_sequence']==1
        # UUID global ocupado por A confirmado: B recibe solo identidad no disponible.
        tx.commit()
        occupied=json.loads(bytes.fromhex(original['body_hex']))['id']
        conflict=await auth_client.post('/api/v1/gardens',json={'id':occupied,'name':'No apropiarse'},headers=headers(actors.b))
        assert conflict.status_code==409 and conflict.json()['detail']['code']=='identity_unavailable'
    finally:
        if tx.is_active: tx.rollback()
        c.close()

@pytest.mark.postgres
@pytest.mark.anyio
@pytest.mark.parametrize('height',[5e-324,1.7976931348623157e308,1e21])
async def test_binary64_dimension_roundtrip_and_etag(actors,auth_client,height):
    result=await auth_client.post('/api/v1/plants',json={'name':'Extremo','watering_frequency_days':1,'initial_height_m':height},headers=headers(actors.a))
    assert result.status_code==201
    get=await auth_client.get(result.headers['location'],headers=actors.a)
    assert get.content==result.content and get.headers['etag']==result.headers['etag']
    assert float(get.json()['initial_height_m'])==height

@pytest.mark.parametrize('failures',[2,3])
def test_transient_retry_keeps_identity_and_has_bound(failures):
    from contextlib import contextmanager
    from types import SimpleNamespace
    calls=[]; committed=[]; operation=uuid4(); frozen=canonical(operation,'garden.create',None,{'name':'Intento'})
    class Transient(Exception): sqlstate='40001'
    class Connection:
        def scalar(self,statement,params):
            calls.append(params)
            if len(calls)<=failures: raise DBAPIError('synthetic',{},Transient(),False)
            return {'status':201}
    repository=ResourceRepository(SimpleNamespace(schema='"test"'))
    @contextmanager
    def transaction(access):
        yield SimpleNamespace(connection=Connection())
        committed.append(True)
    repository.transaction=transaction
    if failures==3:
        with pytest.raises(DBAPIError): repository.apply('synthetic',operation,frozen)
        assert not committed
    else:
        assert repository.apply('synthetic',operation,frozen)=={'status':201} and committed==[True]
    assert len(calls)==3 and all(p=={'id':operation,'request':frozen} for p in calls)

@pytest.mark.postgres
@pytest.mark.anyio
async def test_same_key_is_scoped_to_authenticated_owner(actors,auth_client,auth_db):
    op=uuid4(); body={'name':'Sin fuga'}
    a=await auth_client.post('/api/v1/gardens',json=body,headers=headers(actors.a,op))
    b=await auth_client.post('/api/v1/gardens',json=body,headers=headers(actors.b,op))
    assert a.status_code==b.status_code==201 and a.json()['id']!=b.json()['id']
    assert (await auth_client.post('/api/v1/gardens',json=body,headers=headers(actors.a,op))).content==a.content
    assert (await auth_client.get(a.headers['location'],headers=actors.b)).status_code==404
