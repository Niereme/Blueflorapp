"""Reglas de jardines y límites de cada transacción."""
from app.modules.common.repository import conflict
from app.modules.gardens import repository as rows


class GardenService:
    def __init__(self, repository):
        self.repository = repository

    def create(self, access, body):
        with self.repository.transaction(access) as tx:
            return rows.create(tx,body.model_dump())

    def list(self, access, limit, offset):
        with self.repository.transaction(access) as tx:
            return rows.listing(tx,limit,offset)

    def get(self, access, identifier):
        with self.repository.transaction(access) as tx:
            return rows.get(tx,identifier)

    def patch(self, access, identifier, body):
        with self.repository.transaction(access) as tx:
            rows.get(tx,identifier,lock=True)
            return rows.patch(tx,identifier,body.model_dump(exclude_unset=True))

    def delete(self, access, identifier):
        with self.repository.transaction(access) as tx:
            rows.get(tx,identifier,lock=True)
            if rows.has_plants(tx,identifier):
                raise conflict()
            rows.remove(tx,identifier)
