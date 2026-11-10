"""Exact two-form CHECK compatibility: independent offline and R1 negatives."""
from copy import deepcopy
import json
from pathlib import Path

import pytest
from sqlalchemy import text
from app.core.config import BACKEND_ROOT
from app.db.connection import DatabaseConfigurationError,verify_database
from app.db.restore_comparison import compare_inventories,InventoryMismatch,load_contract
from app.modules.common.repository import ResourceRepository
from test_auth import auth_db
from test_check_restore_diagnostic import NAME,RAW,ORIGINAL,RESTORED


def inventories():
    catalog=json.loads((BACKEND_ROOT/'migrations/versions/0005_capability_manifest.json').read_text())
    a={'catalog':catalog,'database':{'encoding':'UTF8','collate':'en_US.UTF-8','ctype':'en_US.UTF-8','provider':'c','collversion':'2.43'}}
    b=deepcopy(a)
    for role in ('M','R'):b['catalog']['roles'][role]['login']=False
    return a,b


def check(snapshot):
    return next(c for c in snapshot['catalog']['tables']['growth_history']['constraints'] if c.get('expression') in (ORIGINAL,RESTORED))


@pytest.mark.parametrize('left',[ORIGINAL,RESTORED])
@pytest.mark.parametrize('right',[ORIGINAL,RESTORED])
def test_offline_accepts_only_two_forms_without_modifying_inputs(left,right):
    a,b=inventories();check(a)['expression']=left;check(b)['expression']=right
    original=deepcopy((a,b))
    assert compare_inventories(a,b)['result']=='MATCH'
    assert (a,b)==original


OFFLINE_BAD=['missing','true','null','extra_value','weakened','duplicate','type','collation','validated','enforced','deferrable','columns','capability','other_acl','other_check','wrong_boolean_type']
@pytest.mark.parametrize('bad',OFFLINE_BAD)
def test_offline_rejects_bad_metadata_even_if_both_inputs_share_it(bad):
    a,b=inventories();t=b['catalog']['tables']['growth_history'];c=check(b)
    if bad=='missing':t['constraints'].remove(c)
    elif bad=='duplicate':t['constraints'].append(deepcopy(c))
    elif bad in ('true','null','extra_value','weakened'):
        c['expression']={'true':'true','null':'NULL::boolean','extra_value':RESTORED.replace("'canopy'","'leaf'"),'weakened':RESTORED+' OR true'}[bad]
    elif bad=='type':next(v for v in t['columns'] if v['name']=='diameter_kind')['type']='character varying(21)'
    elif bad=='collation':next(v for v in t['columns'] if v['name']=='diameter_kind')['collation']='pg_catalog.C'
    elif bad in ('validated','enforced'):c[bad]=False
    elif bad=='deferrable':c['deferrable']=True
    elif bad=='columns':c['columns']=['diameter_kind','diameter_m']
    elif bad=='capability':b['catalog']['diameter_check_contract']=False
    elif bad=='wrong_boolean_type':c['validated']=1
    elif bad=='other_acl':t['runtime'].append('UPDATE')
    elif bad=='other_check':next(v for v in t['constraints'] if v is not c and v['type']=='c')['expression']='true'
    # Invalid equivalent target metadata must not be laundered by normalization.
    if bad not in ('other_acl','other_check'):
        source=deepcopy(b)
        for r in ('M','R'):source['catalog']['roles'][r]['login']=True
        a=source
    with pytest.raises(InventoryMismatch):compare_inventories(a,b)


def legacy_sql(expression=ORIGINAL):
    return 'CREATE TABLE public.growth_history (\n    diameter_m double precision,\n    diameter_kind character varying(20),\n    CONSTRAINT '+NAME+' CHECK ('+expression+'),\n);\n'


def test_legacy_requires_exact_saved_ddl_and_database_context():
    a,b=inventories();check(b)['expression']=RESTORED
    for x in (a,b):
        del x['catalog']['diameter_check_contract']
        for column in x['catalog']['tables']['growth_history']['columns']:
            column.pop('collation',None)
    with pytest.raises(InventoryMismatch):compare_inventories(a,b)
    result=compare_inventories(a,b,legacy_ddl=legacy_sql())
    assert result['legacy_evidence']['method']=='saved-pg_dump-DDL-default-column-collation'
    for bad in [legacy_sql().replace('character varying(20),','character varying(20) COLLATE "C",'),legacy_sql().replace(NAME,'other_name'),legacy_sql('true')]:
        with pytest.raises(InventoryMismatch):compare_inventories(a,b,legacy_ddl=bad)
    b['database']['collate']='C'
    with pytest.raises(InventoryMismatch):compare_inventories(a,b,legacy_ddl=legacy_sql())


@pytest.mark.postgres
@pytest.mark.parametrize('expression',[RAW,RESTORED])
def test_r1_accepts_exact_forms(auth_db,expression):
    with auth_db.migrator.begin() as c:
        verify_database(c,'test');s='"'+auth_db.schema+'"'
        c.exec_driver_sql(f'ALTER TABLE {s}.growth_history DROP CONSTRAINT {NAME}')
        c.exec_driver_sql(f'ALTER TABLE {s}.growth_history ADD CONSTRAINT {NAME} CHECK ({expression})')
    with auth_db.runtime.begin() as c:ResourceRepository(auth_db.repository).verify_schema(c)


R1_BAD=['missing','true','null','weakened','extra_value','varchar_type','float_type','collation','not_valid','no_inherit','name','not_null']
@pytest.mark.postgres
@pytest.mark.parametrize('bad',R1_BAD)
def test_r1_rejects_incompatible_shape_properties_and_expression(auth_db,bad):
    with auth_db.runtime.begin() as c:ResourceRepository(auth_db.repository).verify_schema(c)
    with auth_db.migrator.begin() as c:
        verify_database(c,'test');s='"'+auth_db.schema+'"'
        if bad=='varchar_type':c.exec_driver_sql(f'ALTER TABLE {s}.growth_history ALTER COLUMN diameter_kind TYPE varchar(21)')
        elif bad=='float_type':c.exec_driver_sql(f'ALTER TABLE {s}.growth_history ALTER COLUMN diameter_m TYPE numeric')
        elif bad=='collation':c.exec_driver_sql(f'ALTER TABLE {s}.growth_history ALTER COLUMN diameter_kind TYPE varchar(20) COLLATE pg_catalog."C"')
        elif bad=='not_null':c.exec_driver_sql(f'ALTER TABLE {s}.growth_history ALTER COLUMN diameter_kind SET NOT NULL')
        elif bad=='name':c.exec_driver_sql(f'ALTER TABLE {s}.growth_history RENAME CONSTRAINT {NAME} TO unexpected_check')
        else:
            c.exec_driver_sql(f'ALTER TABLE {s}.growth_history DROP CONSTRAINT {NAME}')
            if bad!='missing':
                expression={'true':'TRUE','null':'NULL::boolean','weakened':RAW+' OR TRUE','extra_value':RAW.replace("'canopy'","'canopy','leaf'")}.get(bad,RAW)
                suffix={'not_valid':' NOT VALID','no_inherit':' NO INHERIT'}.get(bad,'')
                c.exec_driver_sql(f'ALTER TABLE {s}.growth_history ADD CONSTRAINT {NAME} CHECK ({expression})'+suffix)
    with auth_db.runtime.begin() as c:
        with pytest.raises(DatabaseConfigurationError):ResourceRepository(auth_db.repository).verify_schema(c)
