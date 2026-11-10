"""Validación de relaciones y conservación histórica, independiente del SQL."""
from app.modules.plants import repository as rows


class PlantService:
    def __init__(self, repository):
        self.repository = repository

    def list(self, access, limit, offset, include_deleted=False):
        with self.repository.transaction(access) as tx:
            return rows.listing(tx,limit,offset,include_deleted)

    def get(self, access, identifier):
        with self.repository.transaction(access) as tx:
            return rows.get(tx,identifier,active=True)



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
