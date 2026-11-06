from datetime import datetime
from typing import Literal
from uuid import UUID
from pydantic import BaseModel, Field, model_validator
from app.modules.common.schemas import Dimension, Frequency, Identified, Measured, Name, Patch, Timestamp


class PlantCreate(Identified, Measured):
    name: Name
    garden_id: UUID | None = None
    species_id: UUID | None = None
    species_label: str | None = Field(default=None, max_length=250)
    initial_height_m: Dimension | None = None
    watering_frequency_days: Frequency
    last_watered_at: Timestamp | None = None


class PlantPatch(Patch):
    name: Name | None = None
    garden_id: UUID | None = None
    species_id: UUID | None = None
    species_label: str | None = Field(default=None, max_length=250)
    initial_height_m: Dimension | None = None
    watering_frequency_days: Frequency | None = None

    @model_validator(mode='after')
    def required_fields(self):
        for name in ('name', 'watering_frequency_days'):
            if name in self.model_fields_set and getattr(self, name) is None:
                raise ValueError('Campo obligatorio.')
        return self


class PlantRead(BaseModel):
    id: UUID
    garden_id: UUID | None
    species_id: UUID | None
    name: str
    species_label: str | None
    initial_height_m: float | None
    watering_frequency_days: int
    last_watered_at: datetime | None
    revision: int
    deleted_at: datetime | None
    created_at: datetime
    updated_at: datetime


class SpeciesRead(BaseModel):
    id: UUID
    scientific_name: str
    common_name: str | None
    description: str | None
    source: str | None


class GrowthCreate(Identified, Measured):
    measured_at: Timestamp
    height_m: Dimension | None = None
    diameter_m: Dimension | None = None
    diameter_kind: Literal['stem','canopy'] | None = None
    notes: str | None = Field(default=None,max_length=4000)

    @model_validator(mode='after')
    def valid_dimensions(self):
        if self.height_m is None and self.diameter_m is None:
            raise ValueError('Indica altura o diámetro.')
        if (self.diameter_m is None) != (self.diameter_kind is None):
            raise ValueError('Indica el tipo de diámetro junto con su medida.')
        return self


class GrowthRead(BaseModel):
    id: UUID
    plant_id: UUID | None
    plant_ref_id: UUID
    plant_name_snapshot: str
    height_m: float | None
    diameter_m: float | None
    diameter_kind: str | None
    measured_at: datetime
    recorded_at: datetime
    notes: str | None
