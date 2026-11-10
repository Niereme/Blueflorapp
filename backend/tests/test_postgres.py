"""Pruebas reales: todas las escrituras y el DDL terminan en ROLLBACK.

No se migra public, no se truncan tablas y no se conecta a desarrollo.
"""
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import delete, inspect, insert, select, text, update
from sqlalchemy.exc import IntegrityError, DBAPIError

from app.core.config import BACKEND_ROOT, Settings
from app.db.base import Base
from app.db.connection import create_database_engine, set_owner, verify_database
from app.modules.common.models import identities
from app.db.models import Garden, GrowthHistory, Plant, Species, User, WateringEvent

pytestmark = pytest.mark.postgres
NOW = datetime(2026, 11, 5, 18, tzinfo=timezone.utc)


def migration_config(connection, schema):
    config = Config(str(BACKEND_ROOT / "alembic.ini"))
    config.attributes.update(connection=connection, test_schema=schema)
    return config


@pytest.fixture
def db():
    settings = Settings()
    if settings.test_database_url is None:
        pytest.skip("Configura BLUEFLORA_TEST_DATABASE_URL para pruebas PostgreSQL reales.")
    engine = create_database_engine(settings, "test")
    try:
        connection = engine.connect()
    except Exception:
        engine.dispose()
        pytest.fail("No se pudo conectar a blueflora_test (credenciales omitidas).", pytrace=False)
    transaction = connection.begin()
    schema = f"bf_test_{uuid4().hex}"
    try:
        verify_database(connection, "test")
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))
        connection.execute(text(f'SET LOCAL search_path = "{schema}", pg_catalog'))
        command.upgrade(migration_config(connection, schema), "head")
        yield connection, schema
    finally:
        transaction.rollback()
        connection.close()
        engine.dispose()


def owner(connection):
    value = uuid4()
    set_owner(connection, value)
    connection.execute(insert(User).values(id=value, email=f"{value}@test.invalid"))
    return value


def plant(connection, owner_id, **values):
    result = dict(id=uuid4(), owner_id=owner_id, name="Mi planta", watering_frequency_days=3)
    result.update(values)
    connection.execute(insert(identities).values(id=result["id"],owner_id=owner_id,state="full",revision=1))
    connection.execute(insert(Plant).values(**result))
    return result["id"]


def event(connection, owner_id, plant_id, **values):
    result = dict(id=uuid4(), owner_id=owner_id, plant_id=plant_id,
                  plant_ref_id=plant_id or uuid4(), plant_name_snapshot="Nombre histórico", occurred_at=NOW)
    result.update(values)
    if plant_id is None:
        connection.execute(insert(identities).values(id=result['plant_ref_id'],owner_id=owner_id,state='historical_only',revision=1))
    connection.execute(insert(WateringEvent).values(**result))
    return result["id"]


def rejects(connection, statement):
    with pytest.raises(IntegrityError):
        with connection.begin_nested():
            connection.execute(statement)


def test_initial_migration_matches_models_and_reverses_in_isolation(db):
    c, schema = db
    tables = set(inspect(c).get_table_names(schema=schema))
    assert tables == set(Base.metadata.tables) | {"alembic_version"}
    assert c.scalar(text(f'SELECT version_num FROM "{schema}".alembic_version')) == "0005_mutation_gateway"
    context = MigrationContext.configure(c, opts={"compare_type": True})
    assert compare_metadata(context, Base.metadata) == []
    config = migration_config(c, schema)
    with pytest.raises(RuntimeError,match='corregir hacia delante'):
        command.downgrade(config, "base")
    assert c.scalar(text(f'SELECT version_num FROM "{schema}".alembic_version'))=='0005_mutation_gateway'


def test_uuid_duplicate_names_and_optional_fields_round_trip(db):
    c, _ = db
    o = owner(c)
    first = plant(c, o, initial_height_m=1.25, species_label="Texto de Flutter", last_watered_at=NOW)
    second = plant(c, o)
    rows = c.execute(select(Plant.__table__).order_by(Plant.created_at)).mappings().all()
    assert {row['id'] for row in rows} == {first, second}
    assert all(row['garden_id'] is None and row['species_id'] is None for row in rows)
    assert c.scalar(select(Plant.last_watered_at).where(Plant.id == first)) == NOW
    assert c.scalar(select(Plant.initial_height_m).where(Plant.id == first)) == 1.25


@pytest.mark.parametrize("changes", [
    {"name": "   "}, {"watering_frequency_days": 0}, {"watering_frequency_days": 36501},
    {"initial_height_m": 0}, {"initial_height_m": -1}, {"initial_height_m": float("inf")},
    {"initial_height_m": float("nan")}, {"revision": 0},
])
def test_invalid_plants_are_rejected(db, changes):
    c, _ = db
    o = owner(c)
    values = dict(id=uuid4(), owner_id=o, name="Planta", watering_frequency_days=1)
    values.update(changes)
    rejects(c, insert(Plant).values(**values))


def test_cross_owner_garden_fk_is_rejected(db):
    c, _ = db
    first = owner(c)
    garden = uuid4()
    c.execute(insert(Garden).values(id=garden, owner_id=first, name="Jardín"))
    second = owner(c)
    rejects(c, insert(Plant).values(id=uuid4(), owner_id=second, garden_id=garden, name="Otra", watering_frequency_days=1))


def test_rls_hides_rows_and_blocks_foreign_writes(db):
    c, _ = db
    first = owner(c)
    p = plant(c, first)
    event(c, first, p)
    second = owner(c)
    for model in (Plant, WateringEvent, GrowthHistory, Garden):
        assert c.execute(select(model.__table__)).all() == []
    assert c.execute(select(User.id)).scalars().all() == [second]
    assert c.execute(update(Plant).where(Plant.id == p).values(name="Intrusión")).rowcount == 0
    with pytest.raises(DBAPIError):
        with c.begin_nested():
            plant(c, first)
    rejects(c, insert(WateringEvent).values(id=uuid4(), owner_id=second, plant_id=p,
            plant_ref_id=p, plant_name_snapshot="No autorizada", occurred_at=NOW))
    c.execute(text("SELECT set_config('blueflora.owner_id', '', true)"))
    assert c.execute(select(User.id)).all() == []
    assert c.execute(select(Plant.id)).all() == []


def test_hard_delete_retains_watering_and_growth_history(db):
    c, _ = db
    o = owner(c)
    p = plant(c, o)
    e = event(c, o, p)
    c.execute(insert(GrowthHistory).values(id=uuid4(), owner_id=o, plant_id=p,
        plant_ref_id=p, plant_name_snapshot="Antes", height_m=1.4, measured_at=NOW))
    rejects(c,delete(Plant).where(Plant.id == p))
    row = c.execute(select(WateringEvent.__table__).where(WateringEvent.id == e)).mappings().one()
    assert row['plant_id'] == p and row['plant_ref_id'] == p and row['owner_id'] == o
    growth = c.execute(select(GrowthHistory.__table__)).mappings().one()
    assert growth['plant_id'] == p and growth['plant_ref_id'] == p
    assert growth['owner_id'] == o


def test_deleted_plant_import_needs_no_placeholder(db):
    c, _ = db
    o = owner(c)
    e = event(c, o, None)
    assert c.execute(select(Plant.id)).all() == []
    assert c.scalar(select(WateringEvent.id)) == e


def test_manual_event_uuid_deduplicates_and_timezones_preserve_instant(db):
    c, _ = db
    o = owner(c)
    p = plant(c, o)
    local = NOW.astimezone(timezone(timedelta(hours=-6)))
    e = event(c, o, p, occurred_at=local)
    rejects(c, insert(WateringEvent).values(id=e, owner_id=o, plant_id=p,
        plant_ref_id=p, plant_name_snapshot="Duplicado", occurred_at=local))
    assert c.execute(select(WateringEvent.id)).scalars().all() == [e]
    value = c.scalar(select(WateringEvent.occurred_at))
    assert value == NOW and value.utcoffset() == timedelta(0)


def test_plant_and_event_rollback_together(db):
    c, _ = db
    o = owner(c)
    p = plant(c, o)
    with pytest.raises(IntegrityError):
        with c.begin_nested():
            c.execute(update(Plant).where(Plant.id == p).values(last_watered_at=NOW))
            event(c, o, p, event_type="pump")
    assert c.scalar(select(Plant.last_watered_at)) is None
    assert c.execute(select(WateringEvent.id)).all() == []


def test_history_order_and_snapshot_survive_rename(db):
    c, _ = db
    o = owner(c)
    p = plant(c, o)
    older = event(c, o, p, occurred_at=NOW-timedelta(days=1))
    newer = event(c, o, p)
    c.execute(update(Plant).where(Plant.id == p).values(name="Nuevo nombre"))
    rows = c.execute(select(WateringEvent.id, WateringEvent.plant_name_snapshot)
                     .order_by(WateringEvent.occurred_at.desc(), WateringEvent.id.desc())).all()
    assert [r.id for r in rows] == [newer, older]
    assert all(r.plant_name_snapshot == "Nombre histórico" for r in rows)


@pytest.mark.parametrize("changes", [
    {"height_m": None}, {"height_m": -1}, {"height_m": float("nan")},
    {"diameter_m": 0, "diameter_kind": "stem"},
    {"diameter_m": float("inf"), "diameter_kind": "stem"},
    {"diameter_m": 0.1}, {"diameter_m": 0.1, "diameter_kind": "unknown"},
    {"plant_ref_id": uuid4()},
])
def test_invalid_growth_history_is_rejected(db, changes):
    c, _ = db
    o = owner(c)
    p = plant(c, o)
    values = dict(id=uuid4(), owner_id=o, plant_id=p, plant_ref_id=p,
                  plant_name_snapshot="Planta", height_m=1, measured_at=NOW)
    values.update(changes)
    rejects(c, insert(GrowthHistory).values(**values))


def test_height_and_diameter_independently_optional(db):
    c, _ = db
    o = owner(c)
    p = plant(c, o)
    for changes in ({"height_m": 1.2}, {"diameter_m": 0.05, "diameter_kind": "stem"}):
        c.execute(insert(GrowthHistory).values(id=uuid4(), owner_id=o, plant_id=p,
            plant_ref_id=p, plant_name_snapshot="Planta", measured_at=NOW, **changes))
    assert len(c.execute(select(GrowthHistory.id)).all()) == 2


def test_foreign_owner_history_and_reference_mismatch_rejected(db):
    c, _ = db
    first = owner(c)
    p = plant(c, first)
    second = owner(c)
    rejects(c, insert(GrowthHistory).values(id=uuid4(), owner_id=second, plant_id=p,
        plant_ref_id=p, plant_name_snapshot="Ajena", height_m=1, measured_at=NOW))
    p2 = plant(c, second)
    rejects(c, insert(WateringEvent).values(id=uuid4(), owner_id=second, plant_id=p2,
        plant_ref_id=p, plant_name_snapshot="Incorrecta", occurred_at=NOW))


def test_event_and_growth_columns_use_timestamptz(db):
    c, schema = db
    columns = c.execute(text("""
        SELECT table_name, column_name, data_type
        FROM information_schema.columns
        WHERE table_schema=:schema AND column_name IN
        ('occurred_at','recorded_at','measured_at','last_watered_at','created_at','updated_at','deleted_at')
    """), {"schema": schema}).all()
    assert columns
    assert all(row.data_type == "timestamp with time zone" for row in columns)


def test_user_integrity_and_owner_removal_are_restricted(db):
    c, _ = db
    o = owner(c)
    rejects(c, insert(User).values(id=o, email="another@test.invalid"))
    rejects(c, update(User).where(User.id == o).values(email=" UPPER@TEST.INVALID "))
    rejects(c, update(User).where(User.id == o).values(is_active=True))
    plant(c, o)
    rejects(c, delete(User).where(User.id == o))


def test_missing_owner_is_not_accepted(db):
    c, _ = db
    o = uuid4()
    set_owner(c, o)
    rejects(c, insert(Plant).values(id=uuid4(), owner_id=o, name="Huérfana", watering_frequency_days=1))


def test_soft_delete_keeps_existing_history(db):
    c, _ = db
    o = owner(c)
    p = plant(c, o)
    e = event(c, o, p)
    c.execute(update(Plant).where(Plant.id == p).values(deleted_at=NOW))
    assert c.scalar(select(WateringEvent.plant_id).where(WateringEvent.id == e)) == p
    assert c.scalar(select(Plant.deleted_at).where(Plant.id == p)) == NOW


def test_isolation_includes_gardens_and_growth(db):
    c, _ = db
    first = owner(c)
    p = plant(c, first)
    c.execute(insert(Garden).values(id=uuid4(), owner_id=first, name="Privado"))
    c.execute(insert(GrowthHistory).values(id=uuid4(), owner_id=first, plant_id=p,
        plant_ref_id=p, plant_name_snapshot="Privada", height_m=1, measured_at=NOW))
    owner(c)
    assert c.execute(select(Garden.id)).all() == []
    assert c.execute(select(GrowthHistory.id)).all() == []


def test_migration_rejects_unisolated_test_connection(db):
    c, _ = db
    config = migration_config(c, "public")
    with pytest.raises(RuntimeError, match="esquema propio"):
        command.upgrade(config, "head")
