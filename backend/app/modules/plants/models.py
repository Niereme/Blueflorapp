"""Plantas, catálogo opcional y mediciones; sin reglas HTTP ni sincronización."""
from datetime import datetime
from uuid import UUID, uuid4
from sqlalchemy import (BigInteger, CheckConstraint, DateTime, Double, ForeignKey, ForeignKeyConstraint,
                        Index, Integer, String, Text, UniqueConstraint, func, text)
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class Species(Base):
    __tablename__ = "species"
    __table_args__ = (CheckConstraint("length(btrim(scientific_name)) > 0", name="nonempty_scientific_name"),)
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    scientific_name: Mapped[str] = mapped_column(String(250), unique=True)
    common_name: Mapped[str | None] = mapped_column(String(250))
    description: Mapped[str | None] = mapped_column(Text)
    source: Mapped[str | None] = mapped_column(Text)


class Plant(Base):
    __tablename__ = "plants"
    __table_args__ = (
        UniqueConstraint("owner_id", "id"),
        ForeignKeyConstraint(["owner_id", "id"], ["plant_identities.owner_id", "plant_identities.id"], ondelete="RESTRICT"),
        CheckConstraint("baseline_source IN ('unknown','legacy_snapshot','declared_initial')", name="baseline_source"),
        ForeignKeyConstraint(["owner_id", "garden_id"], ["gardens.owner_id", "gardens.id"], ondelete="RESTRICT"),
        CheckConstraint("length(btrim(name)) > 0", name="nonempty_name"),
        CheckConstraint("watering_frequency_days BETWEEN 1 AND 36500", name="watering_frequency"),
        CheckConstraint("initial_height_m IS NULL OR (initial_height_m > 0 AND initial_height_m < 'Infinity'::float8)", name="positive_finite_height"),
        CheckConstraint("revision > 0", name="positive_revision"),
        Index("ix_plants_owner_garden", "owner_id", "garden_id"),
        Index("ix_plants_owner_deleted", "owner_id", "deleted_at"),
    )
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    garden_id: Mapped[UUID | None]
    species_id: Mapped[UUID | None] = mapped_column(ForeignKey("species.id", ondelete="RESTRICT"), index=True)
    name: Mapped[str] = mapped_column(String(200))
    species_label: Mapped[str | None] = mapped_column(String(250))
    initial_height_m: Mapped[float | None] = mapped_column(Double)
    watering_frequency_days: Mapped[int] = mapped_column(Integer)
    last_watered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    baseline_last_watered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    baseline_source: Mapped[str] = mapped_column(String(30), server_default=text("'unknown'"))
    revision: Mapped[int] = mapped_column(BigInteger, server_default=text("1"))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class GrowthHistory(Base):
    __tablename__ = "growth_history"
    __table_args__ = (
        ForeignKeyConstraint(["owner_id", "plant_ref_id"], ["plant_identities.owner_id", "plant_identities.id"], ondelete="RESTRICT"),
        ForeignKeyConstraint(["owner_id", "plant_id"], ["plants.owner_id", "plants.id"], ondelete="RESTRICT"),
        CheckConstraint("plant_id IS NULL OR plant_id = plant_ref_id", name="matching_plant_reference"),
        CheckConstraint("height_m IS NOT NULL OR diameter_m IS NOT NULL", name="has_measurement"),
        CheckConstraint("height_m IS NULL OR (height_m > 0 AND height_m < 'Infinity'::float8)", name="positive_finite_height"),
        CheckConstraint("diameter_m IS NULL OR (diameter_m > 0 AND diameter_m < 'Infinity'::float8)", name="positive_finite_diameter"),
        CheckConstraint("(diameter_m IS NULL AND diameter_kind IS NULL) OR (diameter_m IS NOT NULL AND diameter_kind IS NOT NULL AND diameter_kind IN ('stem', 'canopy'))", name="diameter_kind"),
        CheckConstraint("length(btrim(plant_name_snapshot)) > 0", name="nonempty_snapshot"),
        Index("ix_growth_history_owner_plant_date", "owner_id", "plant_ref_id", "measured_at"),
        Index("ix_growth_history_owner_link", "owner_id", "plant_id"),
    )
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    plant_id: Mapped[UUID | None]
    plant_ref_id: Mapped[UUID]
    plant_name_snapshot: Mapped[str] = mapped_column(String(200))
    height_m: Mapped[float | None] = mapped_column(Double)
    diameter_m: Mapped[float | None] = mapped_column(Double)
    diameter_kind: Mapped[str | None] = mapped_column(String(20))
    measured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    notes: Mapped[str | None] = mapped_column(Text)
