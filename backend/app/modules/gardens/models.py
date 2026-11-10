"""Instalaciones lógicas sin coordenadas obligatorias."""
from datetime import datetime
from uuid import UUID, uuid4
from sqlalchemy import BigInteger, CheckConstraint, DateTime, ForeignKey, String, Text, UniqueConstraint, func, text
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base


class Garden(Base):
    __tablename__ = "gardens"
    __table_args__ = (
        UniqueConstraint("owner_id", "id"),
        CheckConstraint("revision > 0", name="positive_revision"),
        CheckConstraint("length(btrim(name)) > 0", name="nonempty_name"),
    )
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    revision: Mapped[int] = mapped_column(BigInteger, server_default=text("1"))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
