"""Revisiones e identidades: backfill conservador bajo FORCE RLS."""
from alembic import op
import sqlalchemy as sa
import re

revision = '0004_domain_revisions'
down_revision = '0003_resource_permissions'
branch_labels = depends_on = None


def scope():
    from alembic import context
    schema = context.config.attributes.get('test_schema', 'public')
    if schema != 'public' and not re.fullmatch(r'bf_test_[0-9a-f]{32}', schema):
        raise RuntimeError('Esquema no permitido.')
    return schema, '"'+schema+'"'


def upgrade():
    schema,s = scope()
    c = op.get_bind()
    # RLS nunca se desactiva. Solo la política existente de M permite enumerar IDs.
    previous = c.scalar(sa.text("SELECT current_setting('blueflora.auth_internal',true)"))
    owner_previous = c.scalar(sa.text("SELECT current_setting('blueflora.owner_id',true)"))
    c.execute(sa.text("SELECT set_config('blueflora.auth_internal','on',true)"))
    owners = c.execute(sa.text(f'SELECT id FROM {s}.users ORDER BY id')).scalars().all()
    c.execute(sa.text("SELECT set_config('blueflora.auth_internal',:value,true)"), {'value':previous or ''})
    c.execute(sa.text(f"""CREATE TABLE {s}.plant_identities (
        id uuid PRIMARY KEY, owner_id uuid NOT NULL REFERENCES {s}.users(id) ON DELETE RESTRICT,
        state varchar(30) NOT NULL, revision bigint NOT NULL,
        CONSTRAINT uq_plant_identities_owner_id UNIQUE(owner_id,id),
        CONSTRAINT ck_plant_identities_state CHECK(state IN ('full','historical_only')),
        CONSTRAINT ck_plant_identities_positive_revision CHECK(revision>0))"""))
    c.execute(sa.text(f'ALTER TABLE {s}.plant_identities ENABLE ROW LEVEL SECURITY'))
    c.execute(sa.text(f'ALTER TABLE {s}.plant_identities FORCE ROW LEVEL SECURITY'))
    c.execute(sa.text(f"CREATE POLICY owner_isolation ON {s}.plant_identities USING (owner_id=nullif(current_setting('blueflora.owner_id',true),'')::uuid) WITH CHECK (owner_id=nullif(current_setting('blueflora.owner_id',true),'')::uuid)"))
    op.add_column('gardens',sa.Column('revision',sa.BigInteger(),nullable=False,server_default='1'),schema=schema)
    op.add_column('gardens',sa.Column('updated_at',sa.DateTime(timezone=True)),schema=schema)
    op.add_column('gardens',sa.Column('deleted_at',sa.DateTime(timezone=True)),schema=schema)
    op.create_check_constraint('ck_gardens_positive_revision','gardens','revision>0',schema=schema)
    op.alter_column('plants','revision',type_=sa.BigInteger(),schema=schema)
    op.add_column('plants',sa.Column('baseline_last_watered_at',sa.DateTime(timezone=True)),schema=schema)
    op.add_column('plants',sa.Column('baseline_source',sa.String(30),nullable=False,server_default='unknown'),schema=schema)
    op.create_check_constraint('ck_plants_baseline_source','plants',"baseline_source IN ('unknown','legacy_snapshot','declared_initial')",schema=schema)
    identities = {}
    for owner in owners:
        c.execute(sa.text("SELECT set_config('blueflora.owner_id',:owner,true)"), {'owner':str(owner)})
        c.execute(sa.text(f'UPDATE {s}.gardens SET updated_at=created_at'))
        c.execute(sa.text(f"UPDATE {s}.plants SET baseline_last_watered_at=last_watered_at, baseline_source=CASE WHEN last_watered_at IS NULL THEN 'unknown' ELSE 'legacy_snapshot' END"))
        # Medir imágenes completas, fechas finales y envoltorio de grupo sin truncar.
        dates={'gardens':('created_at','updated_at','deleted_at'),
            'plants':('created_at','updated_at','deleted_at','last_watered_at','baseline_last_watered_at'),
            'growth_history':('recorded_at','measured_at'),'watering_events':('recorded_at','occurred_at')}
        kinds={'gardens':'garden','plants':'plant','growth_history':'growth_measurement','watering_events':'watering_event'}
        for table,fields in dates.items():
            nonfinite=' OR '.join(f'(t.{f} IS NOT NULL AND NOT isfinite(t.{f}))' for f in fields)
            if c.scalar(sa.text(f'SELECT EXISTS(SELECT 1 FROM {s}.{table} t WHERE {nonfinite})')):
                raise RuntimeError('Backfill bloqueado: fecha no finita.')
            image="(to_jsonb(t)-ARRAY['owner_id','revision'])"
            for f in fields:
                image+=f" || jsonb_build_object('{f}',to_char(t.{f} AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'))"
            rev='t.revision::text' if table in ('gardens','plants') else "'1'::text"
            entity=f"jsonb_build_object('entity_type','{kinds[table]}','entity_id',t.id,'revision',{rev},'state',({image}))"
            placeholder="'00000000-0000-0000-0000-000000000000'::text"
            group=f"jsonb_build_object('sequence','9223372036854775807'::text,'change_id',{placeholder},'operation_id',{placeholder},'entities',jsonb_build_array({entity}))"
            if c.scalar(sa.text(f"SELECT EXISTS(SELECT 1 FROM {s}.{table} t WHERE octet_length(convert_to(({group})::text,'UTF8'))>65536)")):
                raise RuntimeError('Backfill bloqueado: imagen/grupo heredado fuera de límite.')
        rows=c.execute(sa.text(f"""SELECT id,revision,'full' state FROM {s}.plants
            UNION ALL SELECT plant_ref_id,1,'historical_only' FROM {s}.watering_events
            UNION ALL SELECT plant_ref_id,1,'historical_only' FROM {s}.growth_history ORDER BY state,id""")).all()
        for identifier,rev,state in rows:
            if identifier in identities:
                if identities[identifier]!=owner:
                    raise RuntimeError('Backfill bloqueado: colisión de identidad.')
                continue
            identities[identifier]=owner
            c.execute(sa.text(f'INSERT INTO {s}.plant_identities(id,owner_id,state,revision) VALUES(:id,:owner,:state,:rev)'),dict(id=identifier,owner=owner,state=state,rev=rev))
    c.execute(sa.text("SELECT set_config('blueflora.owner_id',:owner,true)"), {'owner':owner_previous or ''})
    op.alter_column('gardens','updated_at',nullable=False,server_default=sa.func.now(),schema=schema)
    op.create_foreign_key('fk_plants_owner_id_plant_identities','plants','plant_identities',['owner_id','id'],['owner_id','id'],source_schema=schema,referent_schema=schema,ondelete='RESTRICT')
    for table in ('growth_history','watering_events'):
        op.drop_constraint(f'fk_{table}_owner_id_plants',table,type_='foreignkey',schema=schema)
        op.create_foreign_key(f'fk_{table}_owner_id_plants',table,'plants',['owner_id','plant_id'],['owner_id','id'],source_schema=schema,referent_schema=schema,ondelete='RESTRICT')
        op.create_foreign_key(f'fk_{table}_owner_id_plant_identities',table,'plant_identities',['owner_id','plant_ref_id'],['owner_id','id'],source_schema=schema,referent_schema=schema,ondelete='RESTRICT')
    op.drop_constraint('fk_plants_species_id_species','plants',type_='foreignkey',schema=schema)
    op.create_foreign_key('fk_plants_species_id_species','plants','species',['species_id'],['id'],source_schema=schema,referent_schema=schema,ondelete='RESTRICT')


def downgrade():
    raise RuntimeError('E.4 no admite downgrade destructivo: conservar ledger y datos; corregir hacia delante.')
