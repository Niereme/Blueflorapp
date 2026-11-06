"""Permisos DML explícitos para recursos existentes; no cambia esquema ni RLS."""
import re
from alembic import context, op
import sqlalchemy as sa

revision = "0003_resource_permissions"
down_revision = "0002_auth"
branch_labels = None
depends_on = None


def scope():
    schema = context.config.attributes.get('test_schema', 'public')
    if schema != 'public':
        if not re.fullmatch(r'bf_test_[0-9a-f]{32}', schema):
            raise RuntimeError('Esquema de permisos no permitido.')
        return f'"{schema}"', 'blueflora_api_test'
    if context.is_offline_mode():
        return '"public"', 'blueflora_api'
    database = op.get_bind().scalar(sa.text('SELECT current_database()'))
    if database not in ('blueflora_dev', 'blueflora_test'):
        raise RuntimeError('Base de permisos no permitida.')
    return '"public"', 'blueflora_api' if database == 'blueflora_dev' else 'blueflora_api_test'


def upgrade():
    schema, role = scope()
    op.execute(f'GRANT SELECT, INSERT, DELETE ON {schema}.gardens TO {role}')
    op.execute(f'GRANT UPDATE(name,description) ON {schema}.gardens TO {role}')
    op.execute(f'GRANT SELECT, INSERT ON {schema}.plants TO {role}')
    op.execute(f'''GRANT UPDATE(garden_id,species_id,name,species_label,initial_height_m,
        watering_frequency_days,last_watered_at,revision,deleted_at,updated_at)
        ON {schema}.plants TO {role}''')
    op.execute(f'GRANT SELECT ON {schema}.species TO {role}')
    for table in ('growth_history', 'watering_events'):
        op.execute(f'GRANT SELECT, INSERT ON {schema}.{table} TO {role}')


def downgrade():
    # Solo retira los permisos de esta revisión; no borra datos ni objetos.
    schema, role = scope()
    op.execute(f'REVOKE SELECT, INSERT, DELETE ON {schema}.gardens FROM {role}')
    op.execute(f'REVOKE UPDATE(name,description) ON {schema}.gardens FROM {role}')
    op.execute(f'REVOKE SELECT, INSERT ON {schema}.plants FROM {role}')
    op.execute(f'''REVOKE UPDATE(garden_id,species_id,name,species_label,initial_height_m,
        watering_frequency_days,last_watered_at,revision,deleted_at,updated_at)
        ON {schema}.plants FROM {role}''')
    op.execute(f'REVOKE SELECT ON {schema}.species FROM {role}')
    for table in ('growth_history', 'watering_events'):
        op.execute(f'REVOKE SELECT, INSERT ON {schema}.{table} FROM {role}')
