"""Offline comparison only: exact diameter CHECK v1 and documented NOLOGIN delta.

Never connects to PostgreSQL, rewrites evidence, or executes stored SQL.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path

CONTRACT_PATH=Path(__file__).resolve().parents[2]/'migrations/versions/0005_diameter_check_contract.json'
COMPARATOR_VERSION='bf-restore-inventory-v2'


class InventoryMismatch(ValueError):
    pass


def _same(left,right):
    return json.dumps(left,sort_keys=True,allow_nan=False)==json.dumps(right,sort_keys=True,allow_nan=False)


def load_contract():
    return json.loads(CONTRACT_PATH.read_text())


def legacy_diameter_evidence(sql):
    """Derive default collation/name solely from the exact saved pg_dump DDL.

    Legacy inventories omitted these catalog fields. Report this provenance;
    do not pretend that historical catalogs recorded them.
    """
    rule=load_contract();lines=sql.splitlines()
    if lines.count('CREATE TABLE public.growth_history (')!=1:
        raise InventoryMismatch('Legacy growth DDL unavailable/ambiguous.')
    start=lines.index('CREATE TABLE public.growth_history (')
    try:end=lines.index(');',start)
    except ValueError:raise InventoryMismatch('Incomplete legacy growth DDL.') from None
    block=lines[start+1:end]
    expected={'diameter_m':'    diameter_m double precision,','diameter_kind':'    diameter_kind character varying(20),'}
    for name,line in expected.items():
        matches=[s for s in block if s.lstrip().split(' ',1)[0]==name]
        if matches!=[line]:raise InventoryMismatch('Legacy column DDL not exact.')
    allowed=['    CONSTRAINT '+rule['name']+' CHECK ('+expr+'),' for expr in (rule['original'],rule['reconstructed'])]
    named=[s for s in block if s.lstrip().split(' ',2)[:2]==['CONSTRAINT',rule['name']]]
    if len(named)!=1 or named[0] not in allowed:raise InventoryMismatch('Legacy named CHECK DDL not exact.')
    return {'method':'saved-pg_dump-DDL-default-column-collation','ddl_sha256':hashlib.sha256(sql.encode()).hexdigest(),
            'constraint_name':rule['name'],'collations':{k:v['collation'] for k,v in rule['columns'].items()}}


def _normalize(snapshot,legacy):
    rule=load_contract();result=deepcopy(snapshot)
    try:
        catalog=result['catalog'];table=catalog['tables'][rule['table']]
        if catalog['postgres_major']!=18:raise InventoryMismatch('Unsupported catalog version.')
        modern='diameter_check_contract' in catalog
        if modern and catalog['diameter_check_contract'] is not True:raise InventoryMismatch('Diameter capability not verified.')
        if not modern and legacy is None:raise InventoryMismatch('Legacy collation/name evidence required.')
        for name,profile in rule['columns'].items():
            columns=[c for c in table['columns'] if c['name']==name]
            if len(columns)!=1:raise InventoryMismatch('Diameter columns absent/duplicated.')
            column=columns[0]
            if 'collation' not in column:
                if modern or legacy is None:raise InventoryMismatch('Column collation unavailable.')
                column['collation']=legacy['collations'][name]
            if not _same({k:column[k] for k in profile},profile):raise InventoryMismatch('Diameter column contract mismatch.')
        # Require exactly one full constraint with expected key columns; extra or
        # absent constraints are never silently discarded.
        constraints=table['constraints']
        matches=[c for c in constraints if c.get('type')=='c' and c.get('columns')==rule['constraint']['columns']]
        if len(matches)!=1:raise InventoryMismatch('Diameter CHECK absent/duplicated.')
        check=matches[0]
        if check.get('expression') not in (rule['original'],rule['reconstructed']):raise InventoryMismatch('Unapproved diameter expression.')
        canonical=deepcopy(check);canonical['expression']=rule['original']
        if not _same(canonical,rule['constraint']):raise InventoryMismatch('Diameter CHECK properties mismatch.')
        check['expression']=rule['original']
        # Catalog constraint arrays are deterministic sets; reject differences
        # without relying on their old PostgreSQL JSONB textual sort order.
        table['constraints']=sorted(constraints,key=lambda v:json.dumps(v,sort_keys=True))
        for role in ('M','R'):
            if type(catalog['roles'][role]['login']) is not bool:raise InventoryMismatch('Invalid LOGIN metadata.')
        return result
    except (KeyError,TypeError) as exc:
        raise InventoryMismatch('Incomplete inventory contract.') from exc


def compare_inventories(source,restored,*,legacy_ddl=None):
    """Return technical proof or fail; inputs remain untouched."""
    evidence=legacy_diameter_evidence(legacy_ddl) if legacy_ddl is not None else None
    if source.get('database')!=restored.get('database'):raise InventoryMismatch('Database locale/configuration differs.')
    a=_normalize(source,evidence);b=_normalize(restored,evidence)
    for role in ('M','R'):
        if a['catalog']['roles'][role]['login'] is not True or b['catalog']['roles'][role]['login'] is not False:
            raise InventoryMismatch('Unexpected LOGIN delta.')
        a['catalog']['roles'][role]['login']=False
    if not _same(a,b):raise InventoryMismatch('Other inventory differences remain.')
    return {'result':'MATCH','comparator_version':COMPARATOR_VERSION,'rule_version':load_contract()['version'],
            'rule_sha256':hashlib.sha256(CONTRACT_PATH.read_bytes()).hexdigest(),
            'allowed_differences':['M/R LOGIN true -> false','growth_history diameter CHECK exact two-form equivalence'],
            'legacy_evidence':evidence}
