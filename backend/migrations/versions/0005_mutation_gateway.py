"""Gateway y ACL: activar junto con los ocho escritores, nunca por separado."""
from pathlib import Path
from alembic import context, op
import sqlalchemy as sa
import re
import json

revision='0005_mutation_gateway'
down_revision='0004_domain_revisions'
branch_labels=depends_on=None


def upgrade():
    schema=context.config.attributes.get('test_schema','public')
    if schema!='public' and not re.fullmatch(r'bf_test_[0-9a-f]{32}',schema):
        raise RuntimeError('Esquema no permitido.')
    c=op.get_bind(); s='"'+schema+'"'
    database=c.scalar(sa.text('SELECT current_database()'))
    if database not in ('blueflora_dev','blueflora_test'):
        raise RuntimeError('Destino no permitido.')
    role='blueflora_api_test' if database=='blueflora_test' else 'blueflora_api'
    # All artifacts are versioned next to this migration, independent of cwd.
    directory=Path(__file__).parent
    manifest=json.dumps(json.loads((directory/'0005_capability_manifest.json').read_text()),ensure_ascii=True)
    query=(directory/'0005_capability_query.sql').read_text().strip().rstrip(';')
    query=query.replace('__SCHEMA__',schema).replace('__OWNER__',database).replace('__RUNTIME__',role)
    diameter=json.dumps(json.loads((directory/'0005_diameter_check_contract.json').read_text()),ensure_ascii=True)
    query=query.replace('__DIAMETER_CONTRACT__',diameter)
    gateway=Path(__file__).with_suffix('.sql').read_text()
    gateway=gateway.replace('__CAPABILITY_QUERY__',query).replace('__CAPABILITY_MANIFEST__',manifest).replace('__S__',s)
    c.exec_driver_sql(gateway, execution_options={'no_parameters':True})
    for table in ('sync_owner_state','sync_operations','sync_change_groups'):
        c.execute(sa.text(f'ALTER TABLE {s}.{table} ENABLE ROW LEVEL SECURITY'))
        c.execute(sa.text(f'ALTER TABLE {s}.{table} FORCE ROW LEVEL SECURITY'))
        c.execute(sa.text(f"CREATE POLICY owner_isolation ON {s}.{table} USING(owner_id=nullif(current_setting('blueflora.owner_id',true),'')::uuid) WITH CHECK(owner_id=nullif(current_setting('blueflora.owner_id',true),'')::uuid)"))
    previous=c.scalar(sa.text("SELECT current_setting('blueflora.auth_internal',true)"))
    owner_previous=c.scalar(sa.text("SELECT current_setting('blueflora.owner_id',true)"))
    c.execute(sa.text("SELECT set_config('blueflora.auth_internal','on',true)"))
    owners=c.execute(sa.text(f'SELECT id FROM {s}.users ORDER BY id')).scalars().all()
    c.execute(sa.text("SELECT set_config('blueflora.auth_internal',:value,true)"),{'value':previous or ''})
    for owner in owners:
        c.execute(sa.text("SELECT set_config('blueflora.owner_id',:owner,true)"),{'owner':str(owner)})
        c.execute(sa.text(f'INSERT INTO {s}.sync_owner_state(owner_id) VALUES(:owner)'),{'owner':owner})
    c.execute(sa.text("SELECT set_config('blueflora.owner_id',:owner,true)"),{'owner':owner_previous or ''})
    for table in ('plant_identities','sync_owner_state','sync_operations','sync_change_groups'):
        c.execute(sa.text(f'REVOKE ALL ON {s}.{table} FROM PUBLIC,{role}'))
    for table in ('sync_operations','sync_change_groups','growth_history','watering_events'):
        c.execute(sa.text(f'CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON {s}.{table} FOR EACH ROW EXECUTE FUNCTION {s}.reject_immutable()'))
    c.execute(sa.text(f'REVOKE ALL ON FUNCTION {s}.reject_immutable() FROM {role}'))
    c.execute(sa.text(f'GRANT EXECUTE ON FUNCTION {s}.resource_apply(uuid,text) TO {role}'))
    c.execute(sa.text(f'REVOKE INSERT,DELETE ON {s}.gardens FROM {role}'))
    c.execute(sa.text(f'REVOKE UPDATE(name,description) ON {s}.gardens FROM {role}'))
    c.execute(sa.text(f'REVOKE INSERT ON {s}.plants FROM {role}'))
    c.execute(sa.text(f'REVOKE UPDATE(garden_id,species_id,name,species_label,initial_height_m,watering_frequency_days,last_watered_at,revision,deleted_at,updated_at) ON {s}.plants FROM {role}'))
    for table in ('growth_history','watering_events'):
        c.execute(sa.text(f'REVOKE INSERT ON {s}.{table} FROM {role}'))


def downgrade():
    raise RuntimeError('No reactivar escritores antiguos ni borrar ledger: corregir hacia delante.')
