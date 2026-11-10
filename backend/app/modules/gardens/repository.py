"""Lecturas de jardines; toda mutación pasa por resource_apply."""
from app.modules.gardens.models import Garden
gardens=Garden.__table__

def get(tx,identifier): return tx.one(gardens,identifier,active=True)
def listing(tx,limit,offset,include_deleted=False):
    return tx.page(gardens,limit,offset,conditions=() if include_deleted else (gardens.c.deleted_at.is_(None),))
