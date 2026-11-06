"""Persistencia de eventos manuales dentro de la transacción de la planta."""
from sqlalchemy import insert, select
from app.modules.watering.models import WateringEvent

events=WateringEvent.__table__


def find(tx,identifier):
    row=tx.connection.execute(select(events).where(events.c.id==identifier)).mappings().first()
    return dict(row) if row else None


def create(tx,plant,values):
    return dict(tx.connection.execute(insert(events).values(**values,owner_id=tx.owner_id,
        plant_id=plant['id'],plant_ref_id=plant['id'],plant_name_snapshot=plant['name'],event_type='manual')
        .returning(events)).mappings().one())


def listing(tx,limit,offset,plant_id=None):
    conditions=() if plant_id is None else (events.c.plant_ref_id==plant_id,)
    return tx.page(events,limit,offset,conditions=conditions,
                   order=(events.c.occurred_at.desc(),events.c.id.desc()))


def get(tx,identifier):
    return tx.one(events,identifier)
