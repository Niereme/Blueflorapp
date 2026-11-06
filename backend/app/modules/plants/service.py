"""Validación de relaciones y conservación histórica, independiente del SQL."""
from datetime import datetime, timezone
from app.modules.plants import repository as rows


class PlantService:
    def __init__(self, repository):
        self.repository = repository

    def relations(self, tx, values):
        if values.get('garden_id') is not None:
            rows.garden(tx,values['garden_id'])
        if values.get('species_id') is not None:
            rows.species_get(tx,values['species_id'])

    def create(self, access, body):
        with self.repository.transaction(access) as tx:
            values=body.model_dump()
            self.relations(tx,values)
            return rows.create(tx,values)

    def list(self, access, limit, offset, include_deleted=False):
        with self.repository.transaction(access) as tx:
            return rows.listing(tx,limit,offset,include_deleted)

    def get(self, access, identifier):
        with self.repository.transaction(access) as tx:
            return rows.get(tx,identifier,active=True)

    def patch(self, access, identifier, body):
        with self.repository.transaction(access) as tx:
            rows.get(tx,identifier,lock=True,active=True)
            values=body.model_dump(exclude_unset=True)
            self.relations(tx,values)
            return rows.patch(tx,identifier,values)

    def delete(self, access, identifier):
        with self.repository.transaction(access) as tx:
            plant=rows.get(tx,identifier,lock=True)
            if plant['deleted_at'] is None:
                rows.patch(tx,identifier,{'deleted_at':datetime.now(timezone.utc)})


class SpeciesService:
    def __init__(self, repository):
        self.repository=repository

    def list(self,access,limit,offset):
        with self.repository.transaction(access) as tx:
            return rows.species_list(tx,limit,offset)

    def get(self,access,identifier):
        with self.repository.transaction(access) as tx:
            return rows.species_get(tx,identifier)


class GrowthService:
    def __init__(self,repository):
        self.repository=repository

    def create(self,access,identifier,body):
        with self.repository.transaction(access) as tx:
            plant=rows.get(tx,identifier,lock=True,active=True)
            return rows.growth_create(tx,plant,body.model_dump())

    def list(self,access,limit,offset,plant_id=None):
        with self.repository.transaction(access) as tx:
            return rows.growth_list(tx,limit,offset,plant_id)

    def individual(self,access,identifier,limit,offset):
        with self.repository.transaction(access) as tx:
            rows.get(tx,identifier)  # Borrado lógico no elimina acceso al historial.
            return rows.growth_list(tx,limit,offset,identifier)

    def get(self,access,identifier):
        with self.repository.transaction(access) as tx:
            return rows.growth_get(tx,identifier)
