"""CLI con destino explícito; conexión externa de pruebas con esquema aislado."""
import re
from alembic import context
from sqlalchemy import text
from app.core.config import Settings
from app.db.base import Base
from app.db import models  # noqa: F401
from app.db.connection import create_database_engine, verify_database

config = context.config


def run(connection, schema=None):
    context.configure(connection=connection, target_metadata=Base.metadata,
                      version_table_schema=schema, compare_type=True)
    with context.begin_transaction():
        context.run_migrations()


if context.is_offline_mode():
    context.configure(dialect_name="postgresql", target_metadata=Base.metadata,
                      literal_binds=True, transactional_ddl=True)
    with context.begin_transaction():
        context.run_migrations()
else:
    supplied = config.attributes.get("connection")
    if supplied is not None:
        schema = config.attributes.get("test_schema", "")
        verify_database(supplied, "test")
        if not re.fullmatch(r"bf_test_[0-9a-f]{32}", schema) or not supplied.in_transaction():
            raise RuntimeError("Las pruebas requieren esquema propio y transacción externa.")
        if supplied.scalar(text("SELECT current_schema()")) != schema:
            raise RuntimeError("El search_path no corresponde al esquema de prueba.")
        run(supplied, schema)
    else:
        purpose = context.get_x_argument(as_dictionary=True).get("database", "development")
        if purpose not in ("development", "test"):
            raise RuntimeError("Destino de migraciones inválido.")
        engine = create_database_engine(Settings(), purpose)
        try:
            with engine.begin() as connection:
                verify_database(connection, purpose)
                connection.execute(text("SET LOCAL search_path = public, pg_catalog"))
                run(connection)
        finally:
            engine.dispose()
