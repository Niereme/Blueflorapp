"""Registro manual atómico e idempotencia por UUID; nunca acciona hardware."""
from app.modules.common.repository import conflict
from app.modules.plants import repository as plant_rows
from app.modules.watering import repository as rows


class WateringService:
    def __init__(self,repository):
        self.repository=repository

    def list(self,access,limit,offset,plant_id=None):
        with self.repository.transaction(access) as tx:
            return rows.listing(tx,limit,offset,plant_id)

    def individual(self,access,identifier,limit,offset):
        with self.repository.transaction(access) as tx:
            plant_rows.get(tx,identifier)
            return rows.listing(tx,limit,offset,identifier)

    def get(self,access,identifier):
        with self.repository.transaction(access) as tx:
            return rows.get(tx,identifier)
