"""Consultas parametrizadas y bloqueos de plantas, especies y crecimiento."""
from app.modules.plants.models import GrowthHistory, Plant, Species
from app.modules.gardens.models import Garden

plants = Plant.__table__
species = Species.__table__
growth = GrowthHistory.__table__
gardens = Garden.__table__


def get(tx,identifier,*,lock=False,active=False):
    return tx.one(plants,identifier,lock=lock,active=active)


def species_get(tx,identifier):
    return tx.one(species,identifier)


def listing(tx,limit,offset,include_deleted):
    conditions=() if include_deleted else (plants.c.deleted_at.is_(None),)
    return tx.page(plants,limit,offset,conditions=conditions)


def species_list(tx,limit,offset):
    return tx.page(species,limit,offset,order=(species.c.scientific_name,species.c.id))


def growth_list(tx,limit,offset,plant_id=None):
    conditions=() if plant_id is None else (growth.c.plant_ref_id==plant_id,)
    return tx.page(growth,limit,offset,conditions=conditions,
                   order=(growth.c.measured_at.desc(),growth.c.id.desc()))


def growth_get(tx,identifier):
    return tx.one(growth,identifier)
