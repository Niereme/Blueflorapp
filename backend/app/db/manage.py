"""Comandos de desarrollo que no muestran URLs ni excepciones con secretos."""
import argparse
import sys
from alembic import command
from alembic.config import Config
from sqlalchemy import inspect, text
from app.core.config import BACKEND_ROOT, Settings
from app.db.connection import create_database_engine, verify_database


def main():
    parser = argparse.ArgumentParser(description="PostgreSQL local de BlueFlora")
    parser.add_argument("action", choices=("check", "upgrade", "current", "check-schema"))
    parser.add_argument("--test", action="store_true", help="Usar solo blueflora_test para preparar el esquema de pruebas")
    args = parser.parse_args()
    purpose = "test" if args.test else "development"
    engine = None
    try:
        engine = create_database_engine(Settings(), purpose)
        with engine.connect() as connection:
            verify_database(connection, purpose)
        config = Config(str(BACKEND_ROOT / "alembic.ini"))
        config.cmd_opts = argparse.Namespace(x=[f"database={purpose}"])
        if args.action == "upgrade":
            command.upgrade(config, "head")
            print(f"Migración aplicada a {'blueflora_test' if args.test else 'blueflora_dev'}.")
        elif args.action == "current":
            command.current(config)
        elif args.action == "check-schema":
            command.check(config)
        else:
            with engine.connect() as connection:
                print(f"Conexión local de {purpose} validada.")
                print("Tablas en public:", ", ".join(inspect(connection).get_table_names(schema="public")) or "ninguna")
                print("PostgreSQL:", connection.scalar(text("SHOW server_version")))
    except Exception as exc:
        # Sin traceback ni str(exc): los errores de configuración pueden contener URLs.
        print(f"Operación fallida ({type(exc).__name__}). Revisa configuración, permisos y estado local; no se imprimen credenciales.", file=sys.stderr)
        return 1
    finally:
        if engine is not None:
            engine.dispose()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
