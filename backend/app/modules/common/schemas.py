from datetime import datetime
from typing import Annotated, Generic, TypeVar
from uuid import UUID
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
    if isinstance(value, str):
        import re
        if not re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})', value):
            raise ValueError('Usa RFC3339 con precisión máxima microsegundos.')
    return value


Name = Annotated[str, BeforeValidator(nonblank), Field(max_length=200)]
Timestamp = Annotated[AwareDatetime, BeforeValidator(instant)]
def dimension(value):
    if isinstance(value,int) and not isinstance(value,bool):
        try:
            if int(float(value))!=value: raise ValueError('Medida fuera de precisión binary64.')
        except OverflowError: raise ValueError('Medida fuera de rango.') from None
    return value


Dimension = Annotated[float, BeforeValidator(dimension), Field(gt=0, allow_inf_nan=False, strict=True)]
Frequency = Annotated[int, Field(ge=1, le=36500, strict=True)]
T = TypeVar('T')


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    limit: int
    offset: int


class Identified(Input):
    id: UUID | None = None

    @model_validator(mode='after')
    def nonnull_id(self):
        if 'id' in self.model_fields_set and self.id is None:
            raise ValueError('UUID obligatorio si se declara.')
        return self


class Measured(Input):
    # El reloj es semántica persistente: se comprueba después del ledger en SQL.
    pass
