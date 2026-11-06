"""Entradas cerradas y salidas explícitas sin hashes ni owner_id elegible."""
from datetime import datetime
from uuid import UUID
from email_validator import EmailNotValidError, validate_email
from pydantic import BaseModel, ConfigDict, SecretStr, field_validator


class Credentials(BaseModel):
    model_config = ConfigDict(extra="forbid", hide_input_in_errors=True)
    email: str
    password: SecretStr

    @field_validator('email')
    @classmethod
    def normalized_email(cls, value):
        try:
            if len(value) > 320:
                raise ValueError()
            return validate_email(value.strip(), check_deliverability=False, allow_smtputf8=False).normalized.lower()
        except (EmailNotValidError, ValueError):
            raise ValueError("Correo inválido") from None

    @field_validator('password')
    @classmethod
    def password_size(cls, value):
        if not 1 <= len(value.get_secret_value()) <= 1024:
            raise ValueError("Contraseña inválida")
        return value


class Registration(Credentials):
    @field_validator('password')
    @classmethod
    def password_strength(cls, value):
        if len(value.get_secret_value()) < 12:
            raise ValueError("Usa al menos 12 caracteres")
        return value


class RefreshRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", hide_input_in_errors=True)
    refresh_token: SecretStr

    @field_validator('refresh_token')
    @classmethod
    def token_size(cls, value):
        if len(value.get_secret_value()) > 256:
            raise ValueError("Token inválido")
        return value


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = 900


class AccountResponse(BaseModel):
    id: UUID
    email: str
    is_active: bool
    created_at: datetime


class RegistrationResponse(BaseModel):
    message: str = "Solicitud procesada. Puedes intentar iniciar sesión con tus credenciales."
