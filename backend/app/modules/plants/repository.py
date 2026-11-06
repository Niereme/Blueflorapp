"""Consultas parametrizadas y bloqueos de plantas, especies y crecimiento."""
from sqlalchemy import insert, update, func
from app.modules.plants.models import GrowthHistory, Plant, Species
from app.modules.gardens.models import Garden

plants = Plant.__table__
species = Species.__table__
growth = GrowthHistory.__table__
gardens = Garden.__table__


def get(tx,identifier,*,lock=False,active=False):
    return tx.one(plants,identifier,lock=lock,active=active)


def garden(tx,identifier):
    return tx.one(gardens,identifier,lock=True)


def species_get(tx,identifier):
    return tx.one(species,identifier)


def create(tx,values):
    return dict(tx.connection.execute(insert(plants).values(**values,owner_id=tx.owner_id)
                                     .returning(plants)).mappings().one())


def patch(tx,identifier,values):
    return dict(tx.connection.execute(update(plants).where(plants.c.id==identifier)
        .values(**values,revision=plants.c.revision+1,updated_at=func.clock_timestamp())
        .returning(plants)).mappings().one())


def listing(tx,limit,offset,include_deleted):
    conditions=() if include_deleted else (plants.c.deleted_at.is_(None),)
    return tx.page(plants,limit,offset,conditions=conditions)


def species_list(tx,limit,offset):
    return tx.page(species,limit,offset,order=(species.c.scientific_name,species.c.id))


def growth_create(tx,plant,values):
    return dict(tx.connection.execute(insert(growth).values(**values,owner_id=tx.owner_id,
        plant_id=plant['id'],plant_ref_id=plant['id'],plant_name_snapshot=plant['name'])
        .returning(growth)).mappings().one())


def growth_list(tx,limit,offset,plant_id=None):
    conditions=() if plant_id is None else (growth.c.plant_ref_id==plant_id,)
    return tx.page(growth,limit,offset,conditions=conditions,
                   order=(growth.c.measured_at.desc(),growth.c.id.desc()))


def growth_get(tx,identifier):
    return tx.one(growth,identifier)
