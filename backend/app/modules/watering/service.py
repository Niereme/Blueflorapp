"""Registro manual atómico e idempotencia por UUID; nunca acciona hardware."""
from app.modules.common.repository import conflict
from app.modules.plants import repository as plant_rows
from app.modules.watering import repository as rows


class WateringService:
    def __init__(self,repository):
        self.repository=repository

    def create(self,access,identifier,body):
        with self.repository.transaction(access) as tx:
            plant=plant_rows.get(tx,identifier,lock=True,active=True)
            existing=rows.find(tx,body.id)
            if existing:
                if existing['plant_ref_id']!=identifier or existing['occurred_at']!=body.occurred_at:
                    raise conflict()
                return existing
            event=rows.create(tx,plant,body.model_dump())
            # Un evento antiguo no hace retroceder el calendario existente.
            if plant['last_watered_at'] is None or body.occurred_at>plant['last_watered_at']:
                plant_rows.patch(tx,identifier,{'last_watered_at':body.occurred_at})
            return event

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
