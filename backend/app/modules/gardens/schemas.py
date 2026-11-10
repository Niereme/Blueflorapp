from datetime import datetime
from uuid import UUID
from pydantic import BaseModel, Field, model_validator
from app.modules.common.schemas import Identified, Name, Patch


class GardenCreate(Identified):
    name: Name
    description: str | None = Field(default=None, max_length=4000)


class GardenPatch(Patch):
    name: Name | None = None
    description: str | None = Field(default=None, max_length=4000)

    @model_validator(mode='after')
    def required_name(self):
        if 'name' in self.model_fields_set and self.name is None:
            raise ValueError('El nombre es obligatorio.')
        return self


class GardenRead(BaseModel):
    revision: str
    updated_at: datetime
    deleted_at: datetime | None
    id: UUID
    name: str
    description: str | None
    created_at: datetime
