"""API de recursos y ataques de autorización usando blueflora_api_test real."""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from app.db.connection import set_owner, verify_api
from test_auth import auth_db, auth_client, register, login, bearer

pytestmark=pytest.mark.postgres


def now(): return (datetime.now(timezone.utc)-timedelta(seconds=5)).isoformat()


class ContractClient:
    """Ayuda explícita para conservar los escenarios 3.2D con headers E.4.

    Las pruebas nuevas de protocolo usan auth_client sin esta ayuda.
    """
    def __init__(self,client): self.client=client; self.tags={}
    async def request(self,method,path,**kwargs):
        headers=dict(kwargs.pop('headers',{})); key=(headers.get('Authorization'),path)
        if method in ('POST','PATCH','DELETE'):
            headers.setdefault('Idempotency-Key',str(uuid4()))
        if method in ('PATCH','DELETE'):
            response=await self.client.get(path,headers=headers)
            tag=response.headers.get('etag') or self.tags.get(key)
            kind='garden' if '/gardens/' in path else 'plant'
            headers.setdefault('If-Match',tag or f'"bf1-{kind}-{path.split("/")[-1]}-r1"')
        response=await self.client.request(method,path,headers=headers,**kwargs)
        if response.headers.get('etag'): self.tags[key]=response.headers['etag']
        return response
    async def get(self,path,**kwargs): return await self.request('GET',path,**kwargs)
    async def post(self,path,**kwargs): return await self.request('POST',path,**kwargs)
    async def patch(self,path,**kwargs): return await self.request('PATCH',path,**kwargs)
    async def delete(self,path,**kwargs): return await self.request('DELETE',path,**kwargs)


@pytest.fixture
async def actors(auth_client):
    await register(auth_client)
    await register(auth_client,'bob@example.com')
    a=bearer(await login(auth_client))
    b=bearer(await login(auth_client,'bob@example.com'))
    return SimpleNamespace(client=ContractClient(auth_client),a=a,b=b)


async def plant(actors,**values):
    body={'name':'Lavanda','watering_frequency_days':3,**values}
    response=await actors.client.post('/api/v1/plants',json=body,headers=actors.a)
    assert response.status_code==201
    return response.json()


async def garden(actors,**values):
    response=await actors.client.post('/api/v1/gardens',json={'name':'Patio',**values},headers=actors.a)
    assert response.status_code==201
    return response.json()


@pytest.mark.anyio
async def test_garden_complete_crud_and_pagination(actors):
    c=actors.client
    first=await garden(actors,name='  Patio  ',description='Interior')
    await garden(actors,name='Segundo')
    assert first['name']=='Patio'
    item=await c.get('/api/v1/gardens/'+first['id'],headers=actors.a)
    assert item.status_code==200 and item.json()==first
    page=(await c.get('/api/v1/gardens?limit=1&offset=1',headers=actors.a)).json()
    assert page['total']==2 and page['limit']==1 and page['offset']==1 and len(page['items'])==1
    edited=await c.patch('/api/v1/gardens/'+first['id'],json={'name':'Nuevo','description':None},headers=actors.a)
    assert edited.status_code==200 and edited.json()['description'] is None
    assert (await c.delete('/api/v1/gardens/'+first['id'],headers=actors.a)).status_code==204
    assert (await c.get('/api/v1/gardens/'+first['id'],headers=actors.a)).status_code==404


@pytest.mark.anyio
async def test_garden_restricts_delete_with_active_or_soft_deleted_plants(actors):
    g=await garden(actors)
    p=await plant(actors,garden_id=g['id'])
    path='/api/v1/gardens/'+g['id']
    assert (await actors.client.delete(path,headers=actors.a)).status_code==204
    assert (await actors.client.delete('/api/v1/plants/'+p['id'],headers=actors.a)).status_code==204
    assert (await actors.client.delete(path,headers=actors.a)).status_code==204


@pytest.mark.anyio
async def test_plant_crud_stable_uuid_duplicate_names_and_clear_optional_fields(actors):
    g=await garden(actors)
    identifier=str(uuid4())
    date=now()
    p=await plant(actors,id=identifier,garden_id=g['id'],initial_height_m=1.25,species_label='Lavanda',last_watered_at=date)
    await plant(actors)
    assert p['id']==identifier and p['species_id'] is None
    c=actors.client; path='/api/v1/plants/'+identifier
    assert (await c.get(path,headers=actors.a)).json()==p
    result=await c.patch(path,json={'name':'Otro nombre','garden_id':None,'species_label':None,'initial_height_m':None,'watering_frequency_days':7},headers=actors.a)
    assert result.status_code==200
    edited=result.json()
    assert edited['revision']=='2' and edited['last_watered_at']==p['last_watered_at']
    assert edited['garden_id'] is None and edited['initial_height_m'] is None and edited['species_label'] is None
    assert (await c.get('/api/v1/plants',headers=actors.a)).json()['total']==2
    for _ in range(2): assert (await c.delete(path,headers=actors.a)).status_code==204
    assert (await c.get(path,headers=actors.a)).status_code==404
    assert (await c.get('/api/v1/plants',headers=actors.a)).json()['total']==1
    tombstones=(await c.get('/api/v1/plants?include_deleted=true',headers=actors.a)).json()
    assert tombstones['total']==2 and any(x['deleted_at'] for x in tombstones['items'])


@pytest.mark.anyio
async def test_species_catalog_read_only_with_actual_schema_fields(actors,auth_db):
    identifier=uuid4()
    with auth_db.migrator.begin() as c:
        c.execute(text(f'INSERT INTO "{auth_db.schema}".species(id,scientific_name,common_name,description,source) VALUES(:id,:name,:common,:description,:source)'),
                  {'id':identifier,'name':'Testus exemplaris','common':'Ejemplo de prueba','description':'Solo prueba','source':'Fixture local'})
    c=actors.client
    response=await c.get('/api/v1/species/'+str(identifier),headers=actors.a)
    assert response.status_code==200 and response.json()['source']=='Fixture local'
    assert (await c.get('/api/v1/species?limit=1',headers=actors.b)).json()['total']==1
    p=await plant(actors,species_id=str(identifier))
    assert p['species_id']==str(identifier)
    assert (await c.post('/api/v1/species',json={},headers=actors.a)).status_code==405
    assert (await c.patch('/api/v1/species/'+str(identifier),json={},headers=actors.a)).status_code==405
    assert (await c.delete('/api/v1/species/'+str(identifier),headers=actors.a)).status_code==405


@pytest.mark.anyio
async def test_growth_and_watering_survive_rename_and_logical_delete(actors):
    c=actors.client; p=await plant(actors); path='/api/v1/plants/'+p['id']
    growth=await c.post(path+'/growth-history',json={'measured_at':now(),'height_m':1.4},headers=actors.a)
    assert growth.status_code==201
    event=await c.post(path+'/watering-events',json={'occurred_at':now()},headers=actors.a)
    assert event.status_code==201 and event.json()['event_type']=='manual'
    assert (await c.patch(path,json={'name':'Renombrada'},headers=actors.a)).status_code==200
    assert (await c.delete(path,headers=actors.a)).status_code==204
    for kind,record in (('growth-history',growth.json()),('watering-events',event.json())):
        global_list=(await c.get('/api/v1/'+kind,headers=actors.a)).json()
        assert global_list['total']==1
        individual=(await c.get(path+'/'+kind,headers=actors.a)).json()
        assert individual['items'][0]['plant_ref_id']==p['id']
        assert individual['items'][0]['plant_name_snapshot']=='Lavanda'
        assert (await c.get('/api/v1/'+kind+'/'+record['id'],headers=actors.a)).status_code==200
        body={'occurred_at':now()} if kind=='watering-events' else {'measured_at':now(),'height_m':1}
        assert (await c.post(path+'/'+kind,json=body,headers=actors.a)).status_code==404


@pytest.mark.anyio
async def test_manual_watering_uuid_retry_is_idempotent_and_old_dates_do_not_regress(actors):
    c=actors.client; p=await plant(actors); path='/api/v1/plants/'+p['id']
    latest=now(); body={'id':str(uuid4()),'occurred_at':latest}
    first=await c.post(path+'/watering-events',json=body,headers=actors.a)
    retry=await c.post(path+'/watering-events',json=body,headers=actors.a)
    assert first.status_code==retry.status_code==201 and first.json()==retry.json()
    after=(await c.get(path,headers=actors.a)).json()
    assert after['revision']=='2'
    older=(datetime.now(timezone.utc)-timedelta(days=3)).isoformat()
    assert (await c.post(path+'/watering-events',json={'occurred_at':older},headers=actors.a)).status_code==201
    final=(await c.get(path,headers=actors.a)).json()
    assert final['last_watered_at']==after['last_watered_at'] and final['revision']=='2'
    events=(await c.get('/api/v1/watering-events?limit=1',headers=actors.a)).json()
    assert events['total']==2 and events['items'][0]['id']==body['id']
    conflicting=await c.post(path+'/watering-events',json={**body,'occurred_at':older},headers=actors.a)
    assert conflicting.status_code==409


@pytest.mark.anyio
async def test_water_update_failure_rolls_back_new_event(actors,auth_db):
    c=actors.client; p=await plant(actors)
    me=(await c.get('/api/v1/me',headers=actors.a)).json()
    with auth_db.migrator.begin() as connection:
        set_owner(connection,me['id'])
        connection.execute(text(f'UPDATE "{auth_db.schema}".plants SET revision=9223372036854775807 WHERE id=:id'),{'id':p['id']})
    response=await c.post('/api/v1/plants/'+p['id']+'/watering-events',json={'occurred_at':now()},headers=actors.a)
    assert response.status_code==503
    assert (await c.get('/api/v1/watering-events',headers=actors.a)).json()['total']==0
    assert (await c.get('/api/v1/plants/'+p['id'],headers=actors.a)).json()['last_watered_at'] is None


@pytest.mark.anyio
async def test_foreign_resources_are_indistinguishable_from_missing_and_relations_rejected(actors):
    c=actors.client; g=await garden(actors); p=await plant(actors,garden_id=g['id'])
    for kind,identifier,body in (('gardens',g['id'],{'name':'Intrusión'}),('plants',p['id'],{'name':'Intrusión'})):
        foreign='/api/v1/'+kind+'/'+identifier; absent='/api/v1/'+kind+'/'+str(uuid4())
        for method,payload in (('GET',None),('PATCH',body),('DELETE',None)):
            a=await c.request(method,foreign,json=payload,headers=actors.b)
            b=await c.request(method,absent,json=payload,headers=actors.b)
            assert a.status_code==b.status_code==404 and a.json()==b.json()
    create=await c.post('/api/v1/plants',json={'name':'Ajena','watering_frequency_days':1,'garden_id':g['id']},headers=actors.b)
    assert create.status_code==404
    own=await c.post('/api/v1/plants',json={'name':'Propia','watering_frequency_days':1},headers=actors.b)
    assert own.status_code==201
    assert (await c.patch('/api/v1/plants/'+own.json()['id'],json={'garden_id':g['id']},headers=actors.b)).status_code==404
    for route,body in (('growth-history',{'height_m':1,'measured_at':now()}),('watering-events',{'occurred_at':now()})):
        response=await c.post('/api/v1/plants/'+p['id']+'/'+route,json=body,headers=actors.b)
        assert response.status_code==404
        assert (await c.get('/api/v1/plants/'+p['id']+'/'+route,headers=actors.b)).status_code==404
    assert (await c.get('/api/v1/gardens',headers=actors.b)).json()['total']==0
    assert (await c.get('/api/v1/plants',headers=actors.b)).json()['total']==1


@pytest.mark.anyio
async def test_histories_of_same_named_plants_are_isolated(actors):
    c=actors.client; p=await plant(actors); other=await plant(actors)
    for kind,body in (('growth-history',{'height_m':1,'measured_at':now()}),('watering-events',{'occurred_at':now()})):
        record=await c.post('/api/v1/plants/'+p['id']+'/'+kind,json=body,headers=actors.a)
        assert record.status_code==201
        assert (await c.get('/api/v1/'+kind+'/'+record.json()['id'],headers=actors.b)).status_code==404
        assert (await c.get('/api/v1/'+kind,headers=actors.b)).json()['total']==0
        assert (await c.get('/api/v1/plants/'+other['id']+'/'+kind,headers=actors.a)).json()['total']==0


@pytest.mark.anyio
@pytest.mark.parametrize('field,value',[
    ('name','   '),('watering_frequency_days',0),('watering_frequency_days',36501),
    ('watering_frequency_days',2.5),('watering_frequency_days',True),('initial_height_m',-1),
    ('initial_height_m','Infinity'),('initial_height_m','NaN'),('initial_height_m',True),
    ('last_watered_at','2020-01-01T00:00:00'),('last_watered_at',1234),
    ('owner_id',str(uuid4())),('revision',2),('created_at','2020-01-01T00:00:00Z'),
    ('deleted_at','2020-01-01T00:00:00Z'),('garden_id','bad-uuid'),
])
async def test_plant_validation_and_internal_fields_rejected(actors,field,value):
    body={'name':'Planta','watering_frequency_days':2,field:value}
    assert (await actors.client.post('/api/v1/plants',json=body,headers=actors.a)).status_code==422


@pytest.mark.anyio
@pytest.mark.parametrize('body',[
    {},{'name':None},{'watering_frequency_days':None},{'id':str(uuid4())},
    {'owner_id':str(uuid4())},{'last_watered_at':'2020-01-01T00:00:00Z'},
    {'updated_at':'2020-01-01T00:00:00Z'},{'revision':4},{'deleted_at':None},
])
async def test_plant_patch_cannot_modify_internal_fields_or_clear_required(actors,body):
    p=await plant(actors)
    assert (await actors.client.patch('/api/v1/plants/'+p['id'],json=body,headers=actors.a)).status_code==422


@pytest.mark.anyio
@pytest.mark.parametrize('body',[
    {'measured_at':'2020-01-01T00:00:00Z'},
    {'height_m':-1,'measured_at':'2020-01-01T00:00:00Z'},
    {'height_m':'NaN','measured_at':'2020-01-01T00:00:00Z'},
    {'diameter_m':0,'diameter_kind':'stem','measured_at':'2020-01-01T00:00:00Z'},
    {'diameter_m':0.2,'measured_at':'2020-01-01T00:00:00Z'},
    {'height_m':1,'diameter_kind':'stem','measured_at':'2020-01-01T00:00:00Z'},
    {'height_m':1,'measured_at':'2020-01-01'},
    {'height_m':1,'measured_at':'2999-01-01T00:00:00Z'},
    {'height_m':1,'measured_at':'2020-01-01T00:00:00Z','owner_id':str(uuid4())},
])
async def test_growth_validation(actors,body):
    p=await plant(actors)
    assert (await actors.client.post('/api/v1/plants/'+p['id']+'/growth-history',json=body,headers=actors.a)).status_code==422


@pytest.mark.anyio
async def test_diameter_only_and_offset_datetime_roundtrip(actors):
    p=await plant(actors)
    body={'diameter_m':0.05,'diameter_kind':'stem','measured_at':'2020-01-01T12:00:00-06:00'}
    result=await actors.client.post('/api/v1/plants/'+p['id']+'/growth-history',json=body,headers=actors.a)
    assert result.status_code==201 and result.json()['height_m'] is None
    assert datetime.fromisoformat(result.json()['measured_at'].replace('Z','+00:00'))==datetime(2020,1,1,18,tzinfo=timezone.utc)


@pytest.mark.anyio
@pytest.mark.parametrize('query',['limit=0','limit=101','limit=x','offset=-1','offset=1000001'])
async def test_invalid_pagination(actors,query):
    for path in ('gardens','plants','species','growth-history','watering-events'):
        assert (await actors.client.get('/api/v1/'+path+'?'+query,headers=actors.a)).status_code==422


@pytest.mark.anyio
async def test_all_resource_paths_require_authentication(auth_client):
    identifier=str(uuid4())
    for path in ('gardens','plants','species','growth-history','watering-events',
                 'gardens/'+identifier,'plants/'+identifier,'species/'+identifier,
                 'plants/'+identifier+'/growth-history','plants/'+identifier+'/watering-events'):
        assert (await auth_client.get('/api/v1/'+path)).status_code==401
    for path,body in (('gardens',{'name':'Jardín'}),('plants',{'name':'Planta','watering_frequency_days':1}),
                      ('plants/'+identifier+'/growth-history',{'height_m':1,'measured_at':now()}),
                      ('plants/'+identifier+'/watering-events',{'occurred_at':now()})):
        assert (await auth_client.post('/api/v1/'+path,json=body)).status_code==401


@pytest.mark.anyio
async def test_invalid_uuid_empty_pages_and_unknown_catalog(actors):
    c=actors.client
    for path in ('gardens','plants','species','growth-history','watering-events'):
        assert (await c.get('/api/v1/'+path+'/not-a-uuid',headers=actors.a)).status_code==422
        assert (await c.get('/api/v1/'+path+'?offset=100',headers=actors.a)).json()['items']==[]
    p=await c.post('/api/v1/plants',json={'name':'Planta','watering_frequency_days':1,'species_id':str(uuid4())},headers=actors.a)
    assert p.status_code==404


@pytest.mark.anyio
async def test_rls_using_with_check_and_minimal_privileges(actors,auth_db):
    p=await plant(actors); g=await garden(actors)
    a=(await actors.client.get('/api/v1/me',headers=actors.a)).json()['id']
    b=(await actors.client.get('/api/v1/me',headers=actors.b)).json()['id']
    s=f'"{auth_db.schema}"'
    with auth_db.runtime.begin() as c:
        verify_api(c,'test'); set_owner(c,b)
        assert c.execute(text(f'SELECT id FROM {s}.plants')).all()==[]
        with pytest.raises(DBAPIError):
            with c.begin_nested():
                c.execute(text(f"UPDATE {s}.plants SET name='Otra' WHERE id=:id"),{'id':p['id']})
        for statement,params in [
            (f'INSERT INTO {s}.plants(id,owner_id,name,watering_frequency_days) VALUES(:id,:owner,\'Intrusión\',1)',{'id':uuid4(),'owner':a}),
            (f'UPDATE {s}.plants SET owner_id=:owner WHERE id=:id',{'owner':b,'id':p['id']}),
            (f'DELETE FROM {s}.plants WHERE id=:id',{'id':p['id']}),
            (f'UPDATE {s}.species SET common_name=\'Cambio\'',{}),
            (f'INSERT INTO {s}.species(id,scientific_name) VALUES(:id,\'Inventada\')',{'id':uuid4()}),
            (f'ALTER TABLE {s}.plants DISABLE ROW LEVEL SECURITY',{}),
        ]:
            with pytest.raises(DBAPIError):
                with c.begin_nested(): c.execute(text(statement),params)
        set_owner(c,a)
        # El SET de la expresión cambia el contexto después de USING;
        # WITH CHECK debe impedir confirmar la fila con un propietario distinto.
        with pytest.raises(DBAPIError):
            with c.begin_nested():
                c.execute(text(f"UPDATE {s}.plants SET name=set_config('blueflora.owner_id',:other,true) WHERE id=:id"),{'other':b,'id':p['id']})
        set_owner(c,b)
        with pytest.raises(DBAPIError):
            with c.begin_nested():
                c.execute(text(f"INSERT INTO {s}.plants(id,owner_id,name,watering_frequency_days) VALUES(:id,:owner,'Propia',1)"),{'id':uuid4(),'owner':b})
    with auth_db.migrator.begin() as c:
        c.execute(text(f'CREATE TABLE {s}.future_permission_probe(id uuid)'))
        policies=c.execute(text("SELECT qual,with_check FROM pg_policies WHERE schemaname=:schema AND policyname='owner_isolation' AND tablename IN ('gardens','plants','growth_history','watering_events')"),{'schema':auth_db.schema}).all()
        assert len(policies)==4 and all(using==check and 'blueflora.owner_id' in using for using,check in policies)
    with auth_db.runtime.begin() as c:
        with pytest.raises(DBAPIError):
            with c.begin_nested(): c.execute(text(f'SELECT * FROM {s}.future_permission_probe'))


@pytest.mark.anyio
async def test_history_pagination_filtering_and_descending_order(actors):
    p=await plant(actors); c=actors.client
    for day in (3,1,2):
        date=(datetime.now(timezone.utc)-timedelta(days=day)).isoformat()
        for kind,body in (('growth-history',{'measured_at':date,'height_m':float(day)}),('watering-events',{'occurred_at':date})):
            assert (await c.post('/api/v1/plants/'+p['id']+'/'+kind,json=body,headers=actors.a)).status_code==201
    for kind,field in (('growth-history','measured_at'),('watering-events','occurred_at')):
        response=(await c.get('/api/v1/'+kind+'?limit=2&offset=1&plant_id='+p['id'],headers=actors.a)).json()
        assert response['total']==3 and len(response['items'])==2
        assert response['items'][0][field]>response['items'][1][field]
        assert (await c.get('/api/v1/'+kind+'?plant_id='+str(uuid4()),headers=actors.a)).json()['total']==0


@pytest.mark.anyio
@pytest.mark.parametrize('body',[
    {'occurred_at':'2020-01-01'}, {'occurred_at':1234},
    {'occurred_at':'2999-01-01T00:00:00Z'},
    {'occurred_at':'2020-01-01T00:00:00Z','quantity':1},
    {'occurred_at':'2020-01-01T00:00:00Z','event_type':'pump'},
    {'occurred_at':'2020-01-01T00:00:00Z','plant_ref_id':str(uuid4())},
])
async def test_watering_rejects_invalid_dates_unmodeled_quantities_and_internal_fields(actors,body):
    p=await plant(actors)
    response=await actors.client.post('/api/v1/plants/'+p['id']+'/watering-events',json=body,headers=actors.a)
    assert response.status_code==422


@pytest.mark.anyio
async def test_concurrent_same_uuid_watering_creates_one_event(actors,auth_db):
    from concurrent.futures import ThreadPoolExecutor
    from app.modules.common.repository import ResourceRepository
    from app.modules.common.mutation import canonical
    import json
    p=await plant(actors)
    identifier=uuid4(); op=uuid4()
    payload={'id':str(identifier),'occurred_at':datetime.fromisoformat(now()).astimezone(timezone.utc).isoformat(timespec='microseconds').replace('+00:00','Z')}
    repository=ResourceRepository(auth_db.repository)
    access=actors.a['Authorization'].split(' ',1)[1]
    frozen=canonical(op,'watering_event.create',UUID(p['id']),payload)
    with ThreadPoolExecutor(max_workers=2) as executor:
        result=list(executor.map(lambda _: repository.apply(access,op,frozen),range(2)))
    assert result[0]==result[1] and json.loads(bytes.fromhex(result[0]['body_hex']))['id']==str(identifier)
    page=(await actors.client.get('/api/v1/watering-events',headers=actors.a)).json()
    assert page['total']==1
    assert (await actors.client.get('/api/v1/plants/'+p['id'],headers=actors.a)).json()['revision']=='2'


@pytest.mark.anyio
@pytest.mark.parametrize('literal',['NaN','Infinity','-Infinity'])
async def test_http_nonfinite_dimensions_are_rejected(actors,literal):
    body='{"name":"Planta","watering_frequency_days":1,"initial_height_m":'+literal+'}'
    response=await actors.client.post('/api/v1/plants',content=body,headers={**actors.a,'Content-Type':'application/json'})
    assert response.status_code==422


@pytest.mark.anyio
async def test_garden_internal_fields_and_empty_patch_are_rejected(actors):
    g=await garden(actors)
    c=actors.client
    for body in ({},{'name':None},{'id':str(uuid4())},{'owner_id':str(uuid4())},{'created_at':now()}):
        assert (await c.patch('/api/v1/gardens/'+g['id'],json=body,headers=actors.a)).status_code==422
    assert (await c.post('/api/v1/gardens',json={'name':'Jardín','owner_id':str(uuid4())},headers=actors.a)).status_code==422


@pytest.mark.anyio
async def test_expired_or_revoked_token_cannot_access_resource_endpoints(actors):
    access=actors.a
    assert (await actors.client.post('/api/v1/auth/logout',headers=access)).status_code==204
    assert (await actors.client.get('/api/v1/plants',headers=access)).status_code==401
    assert (await actors.client.post('/api/v1/gardens',json={'name':'Jardín'},headers=access)).status_code==401
