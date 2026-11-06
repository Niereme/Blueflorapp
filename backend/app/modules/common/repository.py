"""Una transacción para validar sesión, fijar propietario y operar con RLS."""
from contextlib import contextmanager
from dataclasses import dataclass
from uuid import UUID
from sqlalchemy import select, func, text
from sqlalchemy.exc import IntegrityError
from fastapi import HTTPException
from app.db.connection import set_owner
from app.modules.auth.security import digest, valid_token
from app.modules.auth.service import unauthorized


def not_found():
    return HTTPException(404, detail={'code':'resource_not_found','message':'Recurso no encontrado.'})


def conflict():
    return HTTPException(409, detail={'code':'resource_conflict','message':'La operación entra en conflicto con los datos actuales.'})


@dataclass
class OwnedSession:
    connection: object
    owner_id: UUID

    def one(self, table, identifier, *, lock=False, active=False):
        statement = select(table).where(table.c.id == identifier)
        if active:
            statement = statement.where(table.c.deleted_at.is_(None))
        if lock:
            statement = statement.with_for_update()
        row = self.connection.execute(statement).mappings().first()
        if row is None:
            raise not_found()
        return dict(row)

    def page(self, table, limit, offset, *, conditions=(), order=None):
        total = self.connection.scalar(select(func.count()).select_from(table).where(*conditions))
        order = order or (table.c.created_at, table.c.id)
        rows = self.connection.execute(select(table).where(*conditions).order_by(*order).limit(limit).offset(offset)).mappings().all()
        return {'items':[dict(row) for row in rows], 'total':total, 'limit':limit, 'offset':offset}


class ResourceRepository:
    def __init__(self, auth_repository):
        self.auth = auth_repository

    @contextmanager
    def transaction(self, access):
        if not valid_token(access, 'a'):
            raise unauthorized()
        try:
            with self.auth.transaction() as connection:
                identity = connection.execute(text(f'SELECT * FROM {self.auth.schema}.auth_access(:hash)'),
                                              {'hash':digest(access)}).mappings().first()
                if identity is None:
                    raise unauthorized()
                set_owner(connection, identity['user_id'])
                connection = connection.execution_options(schema_translate_map={None:self.auth.schema[1:-1]})
                yield OwnedSession(connection, identity['user_id'])
        except IntegrityError:
            # No exponer nombres de constraints, UUID ajenos ni valores SQL.
            raise conflict() from None
