from datetime import datetime, timezone
from typing import Annotated, Generic, TypeVar
from uuid import UUID, uuid4
from pydantic import AwareDatetime, BaseModel, BeforeValidator, ConfigDict, Field, model_validator


class Input(BaseModel):
    model_config = ConfigDict(extra='forbid', hide_input_in_errors=True, allow_inf_nan=False)


class Patch(Input):
    @model_validator(mode='after')
    def nonempty(self):
        if not self.model_fields_set:
            raise ValueError('Indica al menos un campo.')
        return self


def nonblank(value):
    if not isinstance(value, str) or not value.strip():
        raise ValueError('Escribe un nombre válido.')
    return value.strip()


def instant(value):
    if not isinstance(value, (str, datetime)):
        raise ValueError('Usa una fecha ISO 8601 con zona horaria.')
    return value


Name = Annotated[str, BeforeValidator(nonblank), Field(max_length=200)]
Timestamp = Annotated[AwareDatetime, BeforeValidator(instant)]
Dimension = Annotated[float, Field(gt=0, allow_inf_nan=False, strict=True)]
Frequency = Annotated[int, Field(ge=1, le=36500, strict=True)]
T = TypeVar('T')


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    limit: int
    offset: int


class Identified(Input):
    id: UUID = Field(default_factory=uuid4)


class Measured(Input):
    @model_validator(mode='after')
    def not_future(self):
        for field in ('measured_at', 'occurred_at', 'last_watered_at'):
            value = getattr(self, field, None)
            if value is not None and value > datetime.now(timezone.utc):
                raise ValueError('La fecha no puede estar en el futuro.')
        return self
