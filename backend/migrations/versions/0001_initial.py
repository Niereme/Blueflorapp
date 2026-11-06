"""Primer esquema local: seis tablas, UUID, integridad y aislamiento por propietario.

DDL congelado: no importa los modelos vivos al ejecutar revisiones antiguas.
"""
from alembic import context, op

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.execute(
        """
        CREATE TABLE species (
        	id UUID NOT NULL, 
        	scientific_name VARCHAR(250) NOT NULL, 
        	common_name VARCHAR(250), 
        	description TEXT, 
        	source TEXT, 
        	CONSTRAINT pk_species PRIMARY KEY (id), 
        	CONSTRAINT ck_species_nonempty_scientific_name CHECK (length(btrim(scientific_name)) > 0), 
        	CONSTRAINT uq_species_scientific_name UNIQUE (scientific_name)
        )
        """
    )
    op.execute(
        """
        CREATE TABLE users (
        	id UUID NOT NULL, 
        	email VARCHAR(320) NOT NULL, 
        	password_hash TEXT, 
        	is_active BOOLEAN DEFAULT false NOT NULL, 
        	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
        	CONSTRAINT pk_users PRIMARY KEY (id), 
        	CONSTRAINT ck_users_normalized_email CHECK (email = lower(btrim(email)) AND length(email) > 0), 
        	CONSTRAINT ck_users_active_requires_hash CHECK (NOT is_active OR password_hash IS NOT NULL), 
        	CONSTRAINT uq_users_email UNIQUE (email)
        )
        """
    )
    op.execute(
        """
        CREATE TABLE gardens (
        	id UUID NOT NULL, 
        	owner_id UUID NOT NULL, 
        	name VARCHAR(200) NOT NULL, 
        	description TEXT, 
        	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
        	CONSTRAINT pk_gardens PRIMARY KEY (id), 
        	CONSTRAINT uq_gardens_owner_id UNIQUE (owner_id, id), 
        	CONSTRAINT ck_gardens_nonempty_name CHECK (length(btrim(name)) > 0), 
        	CONSTRAINT fk_gardens_owner_id_users FOREIGN KEY(owner_id) REFERENCES users (id) ON DELETE RESTRICT
        )
        """
    )
    op.execute(
        """
        CREATE INDEX ix_gardens_owner_id ON gardens (owner_id)
        """
    )
    op.execute(
        """
        CREATE TABLE plants (
        	id UUID NOT NULL, 
        	owner_id UUID NOT NULL, 
        	garden_id UUID, 
        	species_id UUID, 
        	name VARCHAR(200) NOT NULL, 
        	species_label VARCHAR(250), 
        	initial_height_m DOUBLE PRECISION, 
        	watering_frequency_days INTEGER NOT NULL, 
        	last_watered_at TIMESTAMP WITH TIME ZONE, 
        	revision INTEGER DEFAULT 1 NOT NULL, 
        	deleted_at TIMESTAMP WITH TIME ZONE, 
        	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
        	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
        	CONSTRAINT pk_plants PRIMARY KEY (id), 
        	CONSTRAINT uq_plants_owner_id UNIQUE (owner_id, id), 
        	CONSTRAINT fk_plants_owner_id_gardens FOREIGN KEY(owner_id, garden_id) REFERENCES gardens (owner_id, id) ON DELETE RESTRICT, 
        	CONSTRAINT ck_plants_nonempty_name CHECK (length(btrim(name)) > 0), 
        	CONSTRAINT ck_plants_watering_frequency CHECK (watering_frequency_days BETWEEN 1 AND 36500), 
        	CONSTRAINT ck_plants_positive_finite_height CHECK (initial_height_m IS NULL OR (initial_height_m > 0 AND initial_height_m < 'Infinity'::float8)), 
        	CONSTRAINT ck_plants_positive_revision CHECK (revision > 0), 
        	CONSTRAINT fk_plants_owner_id_users FOREIGN KEY(owner_id) REFERENCES users (id) ON DELETE RESTRICT, 
        	CONSTRAINT fk_plants_species_id_species FOREIGN KEY(species_id) REFERENCES species (id) ON DELETE SET NULL
        )
        """
    )
    op.execute(
        """
        CREATE INDEX ix_plants_owner_deleted ON plants (owner_id, deleted_at)
        """
    )
    op.execute(
        """
        CREATE INDEX ix_plants_owner_garden ON plants (owner_id, garden_id)
        """
    )
    op.execute(
        """
        CREATE INDEX ix_plants_species_id ON plants (species_id)
        """
    )
    op.execute(
        """
        CREATE TABLE growth_history (
        	id UUID NOT NULL, 
        	owner_id UUID NOT NULL, 
        	plant_id UUID, 
        	plant_ref_id UUID NOT NULL, 
        	plant_name_snapshot VARCHAR(200) NOT NULL, 
        	height_m DOUBLE PRECISION, 
        	diameter_m DOUBLE PRECISION, 
        	diameter_kind VARCHAR(20), 
        	measured_at TIMESTAMP WITH TIME ZONE NOT NULL, 
        	recorded_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
        	notes TEXT, 
        	CONSTRAINT pk_growth_history PRIMARY KEY (id), 
        	CONSTRAINT fk_growth_history_owner_id_plants FOREIGN KEY(owner_id, plant_id) REFERENCES plants (owner_id, id) ON DELETE SET NULL (plant_id), 
        	CONSTRAINT ck_growth_history_matching_plant_reference CHECK (plant_id IS NULL OR plant_id = plant_ref_id), 
        	CONSTRAINT ck_growth_history_has_measurement CHECK (height_m IS NOT NULL OR diameter_m IS NOT NULL), 
        	CONSTRAINT ck_growth_history_positive_finite_height CHECK (height_m IS NULL OR (height_m > 0 AND height_m < 'Infinity'::float8)), 
        	CONSTRAINT ck_growth_history_positive_finite_diameter CHECK (diameter_m IS NULL OR (diameter_m > 0 AND diameter_m < 'Infinity'::float8)), 
        	CONSTRAINT ck_growth_history_diameter_kind CHECK ((diameter_m IS NULL AND diameter_kind IS NULL) OR (diameter_m IS NOT NULL AND diameter_kind IS NOT NULL AND diameter_kind IN ('stem', 'canopy'))), 
        	CONSTRAINT ck_growth_history_nonempty_snapshot CHECK (length(btrim(plant_name_snapshot)) > 0), 
        	CONSTRAINT fk_growth_history_owner_id_users FOREIGN KEY(owner_id) REFERENCES users (id) ON DELETE RESTRICT
        )
        """
    )
    op.execute(
        """
        CREATE INDEX ix_growth_history_owner_link ON growth_history (owner_id, plant_id)
        """
    )
    op.execute(
        """
        CREATE INDEX ix_growth_history_owner_plant_date ON growth_history (owner_id, plant_ref_id, measured_at)
        """
    )
    op.execute(
        """
        CREATE TABLE watering_events (
        	id UUID NOT NULL, 
        	owner_id UUID NOT NULL, 
        	plant_id UUID, 
        	plant_ref_id UUID NOT NULL, 
        	plant_name_snapshot VARCHAR(200) NOT NULL, 
        	occurred_at TIMESTAMP WITH TIME ZONE NOT NULL, 
        	recorded_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
        	event_type VARCHAR(30) DEFAULT 'manual' NOT NULL, 
        	CONSTRAINT pk_watering_events PRIMARY KEY (id), 
        	CONSTRAINT fk_watering_events_owner_id_plants FOREIGN KEY(owner_id, plant_id) REFERENCES plants (owner_id, id) ON DELETE SET NULL (plant_id), 
        	CONSTRAINT ck_watering_events_matching_plant_reference CHECK (plant_id IS NULL OR plant_id = plant_ref_id), 
        	CONSTRAINT ck_watering_events_manual_only CHECK (event_type = 'manual'), 
        	CONSTRAINT ck_watering_events_nonempty_snapshot CHECK (length(btrim(plant_name_snapshot)) > 0), 
        	CONSTRAINT fk_watering_events_owner_id_users FOREIGN KEY(owner_id) REFERENCES users (id) ON DELETE RESTRICT
        )
        """
    )
    op.execute(
        """
        CREATE INDEX ix_watering_events_owner_date ON watering_events (owner_id, occurred_at)
        """
    )
    op.execute(
        """
        CREATE INDEX ix_watering_events_owner_link ON watering_events (owner_id, plant_id)
        """
    )
    op.execute(
        """
        CREATE INDEX ix_watering_events_owner_plant_date ON watering_events (owner_id, plant_ref_id, occurred_at)
        """
    )
    op.execute(
        """
        ALTER TABLE users ENABLE ROW LEVEL SECURITY
        """
    )
    op.execute(
        """
        ALTER TABLE users FORCE ROW LEVEL SECURITY
        """
    )
    op.execute(
        """
        CREATE POLICY owner_isolation ON users USING (id = nullif(current_setting('blueflora.owner_id', true), '')::uuid) WITH CHECK (id = nullif(current_setting('blueflora.owner_id', true), '')::uuid)
        """
    )
    op.execute(
        """
        ALTER TABLE gardens ENABLE ROW LEVEL SECURITY
        """
    )
    op.execute(
        """
        ALTER TABLE gardens FORCE ROW LEVEL SECURITY
        """
    )
    op.execute(
        """
        CREATE POLICY owner_isolation ON gardens USING (owner_id = nullif(current_setting('blueflora.owner_id', true), '')::uuid) WITH CHECK (owner_id = nullif(current_setting('blueflora.owner_id', true), '')::uuid)
        """
    )
    op.execute(
        """
        ALTER TABLE plants ENABLE ROW LEVEL SECURITY
        """
    )
    op.execute(
        """
        ALTER TABLE plants FORCE ROW LEVEL SECURITY
        """
    )
    op.execute(
        """
        CREATE POLICY owner_isolation ON plants USING (owner_id = nullif(current_setting('blueflora.owner_id', true), '')::uuid) WITH CHECK (owner_id = nullif(current_setting('blueflora.owner_id', true), '')::uuid)
        """
    )
    op.execute(
        """
        ALTER TABLE growth_history ENABLE ROW LEVEL SECURITY
        """
    )
    op.execute(
        """
        ALTER TABLE growth_history FORCE ROW LEVEL SECURITY
        """
    )
    op.execute(
        """
        CREATE POLICY owner_isolation ON growth_history USING (owner_id = nullif(current_setting('blueflora.owner_id', true), '')::uuid) WITH CHECK (owner_id = nullif(current_setting('blueflora.owner_id', true), '')::uuid)
        """
    )
    op.execute(
        """
        ALTER TABLE watering_events ENABLE ROW LEVEL SECURITY
        """
    )
    op.execute(
        """
        ALTER TABLE watering_events FORCE ROW LEVEL SECURITY
        """
    )
    op.execute(
        """
        CREATE POLICY owner_isolation ON watering_events USING (owner_id = nullif(current_setting('blueflora.owner_id', true), '')::uuid) WITH CHECK (owner_id = nullif(current_setting('blueflora.owner_id', true), '')::uuid)
        """
    )


def downgrade():
    # Solo manual y explícito: nunca parte del arranque o pruebas sobre desarrollo.
    testing = bool(context.config.attributes.get("test_schema"))
    if not testing and context.get_x_argument(as_dictionary=True).get("allow_destructive_downgrade") != "true":
        raise RuntimeError("La reversión elimina las seis tablas. Requiere copia y -x allow_destructive_downgrade=true.")
    op.drop_table('watering_events')
    op.drop_table('growth_history')
    op.drop_table('plants')
    op.drop_table('gardens')
    op.drop_table('users')
    op.drop_table('species')
