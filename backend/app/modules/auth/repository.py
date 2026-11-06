"""La API no recibe una conexión de migración ni SELECT sobre contraseñas."""
from contextlib import contextmanager
import re
from sqlalchemy import text
from app.db.connection import set_owner, verify_api


class AuthRepository:
    def __init__(self, engine, purpose="development", *, schema="public"):
        if schema != "public" and (purpose != "test" or not re.fullmatch(r"bf_test_[0-9a-f]{32}", schema)):
            raise ValueError("Esquema API no permitido.")
        self.schema = f'"{schema}"'
        self.engine = engine
        self.purpose = purpose

    @contextmanager
    def transaction(self):
        with self.engine.begin() as connection:
            verify_api(connection, self.purpose)
            yield connection

    def call(self, name, arguments):
        # Los nombres provienen únicamente de este módulo, nunca de peticiones.
        placeholders = ', '.join(':'+key for key in arguments)
        with self.transaction() as c:
            return c.execute(text(f'SELECT * FROM {self.schema}.{name}({placeholders})'), arguments).mappings().all()

    def attempt(self, key):
        return self.call('auth_attempt', {'p_key': key})[0]['auth_attempt']

    def register(self, user_id, email, password_hash):
        self.call('auth_register', {'p_id': user_id, 'p_email': email, 'p_hash': password_hash})

    def lookup(self, email):
        rows = self.call('auth_lookup', {'p_email': email})
        return rows[0] if rows else None

    def start(self, session_id, user_id, access_hash, refresh_hash):
        return self.call('auth_start_session', {'p_id': session_id, 'p_user': user_id,
                        'p_access': access_hash, 'p_refresh': refresh_hash})[0]['auth_start_session']

    def rotate(self, old_hash, access_hash, refresh_hash):
        # El retorno falso también confirma la transacción: una detección de
        # reutilización debe persistir la revocación, aunque HTTP responda 401.
        return self.call('auth_rotate', {'p_old': old_hash, 'p_access': access_hash,
                                        'p_refresh': refresh_hash})[0]['auth_rotate']

    def logout(self, access_hash):
        self.call('auth_logout', {'p_access': access_hash})

    def account(self, access_hash):
        with self.transaction() as c:
            identity = c.execute(text(f'SELECT * FROM {self.schema}.auth_access(:hash)'), {'hash': access_hash}).mappings().first()
            if identity is None:
                return None
            set_owner(c, identity['user_id'])
            return c.execute(text(f'SELECT id,email,is_active,created_at FROM {self.schema}.users WHERE id=:id'),
                             {'id': identity['user_id']}).mappings().first()
