"""Consultas; reglas persistentes y escrituras exclusivamente en SQL."""
from app.modules.gardens import repository as rows
class GardenService:
    def __init__(self,repository): self.repository=repository
    def list(self,access,limit,offset,include_deleted=False):
        with self.repository.transaction(access) as tx: return rows.listing(tx,limit,offset,include_deleted)
    def get(self,access,identifier):
        with self.repository.transaction(access) as tx: return rows.get(tx,identifier)
