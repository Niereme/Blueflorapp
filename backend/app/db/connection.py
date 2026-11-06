"""Conexiones locales explícitas y protección contra bases equivocadas."""
from contextlib import contextmanager
from typing import Literal
from uuid import UUID

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Connection, make_url
from sqlalchemy.pool import NullPool

from app.core.config import Settings

Purpose = Literal["development", "test"]


class DatabaseConfigurationError(ValueError):
    """Error deliberadamente libre de credenciales."""


def database_url(settings: Settings, purpose: Purpose = "development"):
    if purpose not in ("development", "test"):
        raise DatabaseConfigurationError("Destino de base de datos no permitido.")
    secret = settings.database_url if purpose == "development" else settings.test_database_url
    if secret is None:
        raise DatabaseConfigurationError("Falta configurar la URL PostgreSQL del destino solicitado.")
    try:
        url = make_url(secret.get_secret_value())
        valid = (
            url.drivername == "postgresql+psycopg"
            and url.host in ("localhost", "127.0.0.1", "::1")
            and url.port in (None, 5432)
            and url.username == f"blueflora_{'dev' if purpose == 'development' else 'test'}"
            and url.database == url.username
            and bool(url.password)
            and not url.query  # Impide sobrescribir host/db con parámetros libpq.
        )
    except Exception:
        valid = False
    if not valid:
        raise DatabaseConfigurationError("URL inválida: se exige PostgreSQL local y rol/base exclusivos del destino.")
    return url


def create_database_engine(settings: Settings, purpose: Purpose = "development"):
    return create_engine(
        database_url(settings, purpose), poolclass=NullPool,
        hide_parameters=True, connect_args={"connect_timeout": 5, "options": "-c timezone=UTC"},
    )


def verify_database(connection: Connection, purpose: Purpose):
    expected = "blueflora_dev" if purpose == "development" else "blueflora_test"
    database, user, superuser, bypass = connection.execute(text(
        "SELECT current_database(), current_user, rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user"
    )).one()
    if database != expected or user != expected or superuser or bypass:
        raise DatabaseConfigurationError("Conexión rechazada: identidad o base de datos no permitida.")


def set_owner(connection: Connection, owner_id: UUID):
    """Contexto RLS de una transacción; nunca una sesión global ni un dato confiado al cliente."""
    connection.execute(text("SELECT set_config('blueflora.owner_id', :owner, true)"),
                       {"owner": str(UUID(str(owner_id)))})


@contextmanager
def owner_transaction(engine, owner_id: UUID):
    with engine.begin() as connection:
        verify_database(connection, "development")
        set_owner(connection, owner_id)
        yield connection


def create_api_engine(settings: Settings, purpose: Purpose = "development"):
    """La API nunca utiliza las credenciales de migración como alternativa."""
    if purpose not in ("development", "test"):
        raise DatabaseConfigurationError("Destino API inválido.")
    secret = settings.api_database_url if purpose == "development" else settings.test_api_database_url
    expected_role = "blueflora_api" if purpose == "development" else "blueflora_api_test"
    expected_db = "blueflora_dev" if purpose == "development" else "blueflora_test"
    try:
        url = make_url(secret.get_secret_value())
        valid = (url.drivername == "postgresql+psycopg" and url.host in ("localhost", "127.0.0.1", "::1")
                 and url.port in (None, 5432) and not url.query and bool(url.password)
                 and url.username == expected_role and url.database == expected_db)
    except Exception:
        valid = False
    if not valid:
        raise DatabaseConfigurationError("Falta una conexión API local exclusiva y válida.")
    return create_engine(url, poolclass=NullPool, hide_parameters=True,
                         connect_args={"connect_timeout": 5, "options": "-c timezone=UTC"})


def verify_api(connection: Connection, purpose: Purpose = "development"):
    role = "blueflora_api" if purpose == "development" else "blueflora_api_test"
    database = "blueflora_dev" if purpose == "development" else "blueflora_test"
    row = connection.execute(text("""
        SELECT current_user, current_database(), rolsuper, rolbypassrls, rolcreatedb, rolcreaterole,
               EXISTS(SELECT 1 FROM pg_class WHERE relowner=(SELECT oid FROM pg_roles WHERE rolname=current_user)
                      AND relkind IN ('r','p','v','m')),
               EXISTS(SELECT 1 FROM pg_auth_members WHERE member=(SELECT oid FROM pg_roles WHERE rolname=current_user)),
               has_schema_privilege(current_user,'public','CREATE'),
               has_database_privilege(current_user,current_database(),'CREATE')
        FROM pg_roles WHERE rolname=current_user
    """)).one()
    if row[0] != role or row[1] != database or any(row[2:]):
        raise DatabaseConfigurationError("Rol API rechazado: identidad o privilegios incompatibles.")
