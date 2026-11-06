"""Configuración validada por entorno, sin conexiones ni secretos requeridos."""
from pathlib import Path
from typing import Literal

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="BLUEFLORA_",
        env_file=BACKEND_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    environment: Literal["development", "test", "production"] = "development"
    app_name: str = Field(default="BlueFlora API", min_length=1)
    docs_enabled: bool = True
    database_url: SecretStr | None = None
    test_database_url: SecretStr | None = None
    api_database_url: SecretStr | None = None
    test_api_database_url: SecretStr | None = None
