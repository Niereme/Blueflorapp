from datetime import datetime
from typing import Literal
from uuid import UUID
from pydantic import BaseModel
from app.modules.common.schemas import Identified, Measured, Timestamp


class WateringCreate(Identified,Measured):
    occurred_at: Timestamp


class WateringRead(BaseModel):
    revision: str = "1"
    id: UUID
    plant_id: UUID | None
    plant_ref_id: UUID
    plant_name_snapshot: str
    occurred_at: datetime
    recorded_at: datetime
    event_type: Literal['manual']
