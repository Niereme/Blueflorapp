"""Persistencia de eventos manuales dentro de la transacción de la planta."""
from app.modules.watering.models import WateringEvent

events=WateringEvent.__table__


def listing(tx,limit,offset,plant_id=None):
    conditions=() if plant_id is None else (events.c.plant_ref_id==plant_id,)
    return tx.page(events,limit,offset,conditions=conditions,
                   order=(events.c.occurred_at.desc(),events.c.id.desc()))


def get(tx,identifier):
    return tx.one(events,identifier)
