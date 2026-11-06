"""SQL del módulo de jardines; recibe una transacción API ya autenticada."""
from sqlalchemy import delete, insert, select, update
from app.modules.gardens.models import Garden
from app.modules.plants.models import Plant

gardens = Garden.__table__
plants = Plant.__table__


def create(tx, values):
    return dict(tx.connection.execute(insert(gardens).values(**values,owner_id=tx.owner_id)
                                     .returning(gardens)).mappings().one())


def get(tx, identifier, *, lock=False):
    return tx.one(gardens,identifier,lock=lock)


def listing(tx,limit,offset):
    return tx.page(gardens,limit,offset)


def patch(tx,identifier,values):
    return dict(tx.connection.execute(update(gardens).where(gardens.c.id==identifier)
                                     .values(**values).returning(gardens)).mappings().one())


def has_plants(tx,identifier):
    return tx.connection.scalar(select(plants.c.id).where(plants.c.garden_id==identifier).limit(1)) is not None


def remove(tx,identifier):
    tx.connection.execute(delete(gardens).where(gardens.c.id==identifier))
