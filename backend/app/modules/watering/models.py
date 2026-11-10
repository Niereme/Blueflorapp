"""Eventos manuales: nunca una orden de bomba ni evidencia de caudal."""
from datetime import datetime
from uuid import UUID, uuid4
from sqlalchemy import CheckConstraint, DateTime, ForeignKey, ForeignKeyConstraint, Index, String, func, text
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class WateringEvent(Base):
    __tablename__ = "watering_events"
    __table_args__ = (
        ForeignKeyConstraint(["owner_id", "plant_ref_id"], ["plant_identities.owner_id", "plant_identities.id"], ondelete="RESTRICT"),
        ForeignKeyConstraint(["owner_id", "plant_id"], ["plants.owner_id", "plants.id"], ondelete="RESTRICT"),
        CheckConstraint("plant_id IS NULL OR plant_id = plant_ref_id", name="matching_plant_reference"),
        CheckConstraint("event_type = 'manual'", name="manual_only"),
        CheckConstraint("length(btrim(plant_name_snapshot)) > 0", name="nonempty_snapshot"),
        Index("ix_watering_events_owner_date", "owner_id", "occurred_at"),
        Index("ix_watering_events_owner_plant_date", "owner_id", "plant_ref_id", "occurred_at"),
        Index("ix_watering_events_owner_link", "owner_id", "plant_id"),
    )
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    plant_id: Mapped[UUID | None]
    plant_ref_id: Mapped[UUID]
    plant_name_snapshot: Mapped[str] = mapped_column(String(200))
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    event_type: Mapped[str] = mapped_column(String(30), server_default=text("'manual'"))
