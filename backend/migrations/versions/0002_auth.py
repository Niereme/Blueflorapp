"""Autenticación privada: sesiones, rotación, límites y funciones acotadas."""
import re
from alembic import context, op
import sqlalchemy as sa

revision = "0002_auth"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def scope():
    schema = context.config.attributes.get("test_schema", "public")
    if schema != "public" and not re.fullmatch(r"bf_test_[0-9a-f]{32}", schema):
        raise RuntimeError("Esquema de autenticación no permitido.")
    if schema != "public":
        return schema, "blueflora_test", "blueflora_api_test"
    if context.is_offline_mode():
        return schema, "blueflora_dev", "blueflora_api"
    database = op.get_bind().scalar(sa.text("SELECT current_database()"))
    if database not in ("blueflora_dev", "blueflora_test"):
        raise RuntimeError("Base de autenticación no permitida.")
    return schema, ("blueflora_dev" if database == "blueflora_dev" else "blueflora_test"), ("blueflora_api" if database == "blueflora_dev" else "blueflora_api_test")


def upgrade():
    schema, migrator, api = scope()
    s = f'"{schema}"'
    # DDL congelado, independiente de cambios posteriores a los modelos.
    op.execute(
        """
        CREATE TABLE auth_sessions (
        	id UUID NOT NULL, 
        	user_id UUID NOT NULL, 
        	access_token_hash VARCHAR(64) NOT NULL, 
        	access_expires_at TIMESTAMP WITH TIME ZONE NOT NULL, 
        	expires_at TIMESTAMP WITH TIME ZONE NOT NULL, 
        	revoked_at TIMESTAMP WITH TIME ZONE, 
        	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
        	CONSTRAINT pk_auth_sessions PRIMARY KEY (id), 
        	CONSTRAINT ck_auth_sessions_access_before_session_expiry CHECK (access_expires_at <= expires_at), 
        	CONSTRAINT ck_auth_sessions_positive_lifetime CHECK (expires_at > created_at), 
        	CONSTRAINT ck_auth_sessions_valid_access_hash CHECK (access_token_hash ~ '^[0-9a-f]{64}$'), 
        	CONSTRAINT fk_auth_sessions_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE RESTRICT, 
        	CONSTRAINT uq_auth_sessions_access_token_hash UNIQUE (access_token_hash)
        )
        """
    )
    op.execute(
        """
        CREATE INDEX ix_auth_sessions_expires_at ON auth_sessions (expires_at)
        """
    )
    op.execute(
        """
        CREATE INDEX ix_auth_sessions_user_id ON auth_sessions (user_id)
        """
    )
    op.execute(
        """
        CREATE TABLE auth_refresh_tokens (
        	token_hash VARCHAR(64) NOT NULL, 
        	session_id UUID NOT NULL, 
        	used_at TIMESTAMP WITH TIME ZONE, 
        	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
        	CONSTRAINT pk_auth_refresh_tokens PRIMARY KEY (token_hash), 
        	CONSTRAINT ck_auth_refresh_tokens_valid_token_hash CHECK (token_hash ~ '^[0-9a-f]{64}$'), 
        	CONSTRAINT fk_auth_refresh_tokens_session_id_auth_sessions FOREIGN KEY(session_id) REFERENCES auth_sessions (id) ON DELETE RESTRICT
        )
        """
    )
    op.execute(
        """
        CREATE INDEX ix_auth_refresh_tokens_session_id ON auth_refresh_tokens (session_id)
        """
    )
    op.execute(
        """
        CREATE TABLE auth_rate_limits (
        	key_hash VARCHAR(64) NOT NULL, 
        	window_started_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
        	attempts INTEGER DEFAULT 1 NOT NULL, 
        	CONSTRAINT pk_auth_rate_limits PRIMARY KEY (key_hash), 
        	CONSTRAINT ck_auth_rate_limits_positive_attempts CHECK (attempts > 0), 
        	CONSTRAINT ck_auth_rate_limits_valid_key_hash CHECK (key_hash ~ '^[0-9a-f]{64}$')
        )
        """
    )
    for table in ("auth_sessions", "auth_refresh_tokens", "auth_rate_limits"):
        op.execute(f'ALTER TABLE {s}.{table} ENABLE ROW LEVEL SECURITY')
        op.execute(f'ALTER TABLE {s}.{table} FORCE ROW LEVEL SECURITY')
        predicate = "current_setting('blueflora.auth_internal', true) = 'on'"
        op.execute(f"CREATE POLICY auth_internal ON {s}.{table} TO {migrator} USING ({predicate}) WITH CHECK ({predicate})")
    for action in ("SELECT", "INSERT"):
        clause = "USING" if action == "SELECT" else "WITH CHECK"
        op.execute(f"CREATE POLICY auth_internal_{action.lower()} ON {s}.users FOR {action} TO {migrator} {clause} (current_setting('blueflora.auth_internal', true) = 'on')")

    def function(name, arguments, returns, body):
        # El rol no puede añadir un GUC propio a proconfig. El contexto interno
        # se guarda/restaura explícitamente, incluyendo errores y retornos tempranos.
        result_declaration = "result boolean;" if returns == "boolean" else ""
        result_return = "RETURN result;" if returns == "boolean" else ""
        if returns == "boolean":
            body = re.sub(r"\bRETURN (.*?);", r"result := \1; EXIT operation;", body, flags=re.S)
        op.execute(f"""CREATE FUNCTION {s}.{name}({arguments}) RETURNS {returns}
            LANGUAGE plpgsql SECURITY DEFINER
            SET search_path = pg_catalog, pg_temp
            AS $function$
            DECLARE previous text; {result_declaration}
            BEGIN
                previous := current_setting('blueflora.auth_internal', true);
                PERFORM set_config('blueflora.auth_internal', 'on', true);
                <<operation>> BEGIN {body} END;
                PERFORM set_config('blueflora.auth_internal', coalesce(previous, ''), true);
                {result_return}
            EXCEPTION WHEN OTHERS THEN
                PERFORM set_config('blueflora.auth_internal', coalesce(previous, ''), true);
                RAISE;
            END $function$""")
        # Las firmas no contienen defaults ni sobrecargas.
        signature = ', '.join(item.strip().split()[-1] for item in arguments.split(','))
        op.execute(f'REVOKE ALL ON FUNCTION {s}.{name}({signature}) FROM PUBLIC')
        op.execute(f'GRANT EXECUTE ON FUNCTION {s}.{name}({signature}) TO {api}')

    function("auth_lookup", "p_email text", "TABLE(user_id uuid, password_hash text, is_active boolean)", f"""
        RETURN QUERY SELECT u.id, u.password_hash, u.is_active
        FROM {s}.users AS u WHERE u.email = p_email LIMIT 1;
    """)
    function("auth_register", "p_id uuid, p_email text, p_hash text", "void", f"""
        IF p_hash NOT LIKE '$argon2id$%' OR length(p_hash) > 512 THEN
            RAISE EXCEPTION 'Invalid credential format';
        END IF;
        INSERT INTO {s}.users(id,email,password_hash,is_active)
        VALUES(p_id,p_email,p_hash,true) ON CONFLICT(email) DO NOTHING;
    """)
    function("auth_start_session", "p_id uuid, p_user uuid, p_access text, p_refresh text", "boolean", f"""
        IF NOT EXISTS(SELECT 1 FROM {s}.users WHERE id=p_user AND is_active) THEN RETURN false; END IF;
        INSERT INTO {s}.auth_sessions(id,user_id,access_token_hash,access_expires_at,expires_at)
        VALUES(p_id,p_user,p_access,clock_timestamp()+interval '15 minutes',clock_timestamp()+interval '30 days');
        INSERT INTO {s}.auth_refresh_tokens(token_hash,session_id) VALUES(p_refresh,p_id);
        RETURN true;
    """)
    function("auth_access", "p_hash text", "TABLE(user_id uuid, session_id uuid)", f"""
        RETURN QUERY SELECT a.user_id,a.id FROM {s}.auth_sessions a
        JOIN {s}.users u ON u.id=a.user_id
        WHERE a.access_token_hash=p_hash AND a.revoked_at IS NULL
        AND a.access_expires_at>clock_timestamp() AND a.expires_at>clock_timestamp() AND u.is_active;
    """)
    function("auth_rotate", "p_old text, p_access text, p_refresh text", "boolean", f"""
        DECLARE a {s}.auth_sessions%ROWTYPE; used timestamptz;
        BEGIN
            -- Orden de bloqueo uniforme: sesión primero, refresh después.
            SELECT session.* INTO a FROM {s}.auth_sessions session
            WHERE session.id=(SELECT r.session_id FROM {s}.auth_refresh_tokens r WHERE r.token_hash=p_old)
            FOR UPDATE;
            IF NOT FOUND OR a.revoked_at IS NOT NULL OR a.expires_at<=clock_timestamp() THEN RETURN false; END IF;
            SELECT r.used_at INTO used FROM {s}.auth_refresh_tokens r WHERE r.token_hash=p_old FOR UPDATE;
            IF used IS NOT NULL THEN
                UPDATE {s}.auth_sessions SET revoked_at=clock_timestamp() WHERE id=a.id;
                RETURN false;
            END IF;
            IF NOT EXISTS(SELECT 1 FROM {s}.users WHERE id=a.user_id AND is_active) THEN RETURN false; END IF;
            UPDATE {s}.auth_refresh_tokens SET used_at=clock_timestamp() WHERE token_hash=p_old;
            INSERT INTO {s}.auth_refresh_tokens(token_hash,session_id) VALUES(p_refresh,a.id);
            UPDATE {s}.auth_sessions SET access_token_hash=p_access,
                access_expires_at=least(clock_timestamp()+interval '15 minutes',expires_at) WHERE id=a.id;
            RETURN true;
        END;
    """)
    function("auth_logout", "p_access text", "void", f"""
        UPDATE {s}.auth_sessions SET revoked_at=coalesce(revoked_at,clock_timestamp())
        WHERE access_token_hash=p_access;
    """)
    function("auth_attempt", "p_key text", "boolean", f"""
        INSERT INTO {s}.auth_rate_limits(key_hash,window_started_at,attempts)
        VALUES(p_key,clock_timestamp(),1)
        ON CONFLICT(key_hash) DO UPDATE SET
            attempts=CASE WHEN {s}.auth_rate_limits.window_started_at <= clock_timestamp()-interval '1 minute'
                          THEN 1 ELSE least({s}.auth_rate_limits.attempts+1,11) END,
            window_started_at=CASE WHEN {s}.auth_rate_limits.window_started_at <= clock_timestamp()-interval '1 minute'
                                   THEN clock_timestamp() ELSE {s}.auth_rate_limits.window_started_at END;
        RETURN (SELECT attempts <= 10 FROM {s}.auth_rate_limits WHERE key_hash=p_key);
    """)
    op.execute(f'GRANT SELECT (id,email,is_active,created_at) ON {s}.users TO {api}')
    # Sin permisos de tabla sobre hashes, sesiones o recursos de plantas.


def downgrade():
    if not context.config.attributes.get("test_schema"):
        raise RuntimeError("Reversión de autenticación prohibida fuera de esquemas temporales de pruebas.")
    schema, migrator, api = scope()
    s = f'"{schema}"'
    for name, signature in (("auth_lookup","text"),("auth_register","uuid,text,text"),
                            ("auth_start_session","uuid,uuid,text,text"),("auth_access","text"),
                            ("auth_rotate","text,text,text"),("auth_logout","text"),("auth_attempt","text")):
        op.execute(f'DROP FUNCTION {s}.{name}({signature})')
    for action in ("select", "insert"):
        op.execute(f'DROP POLICY auth_internal_{action} ON {s}.users')
    op.execute(f'REVOKE SELECT(id,email,is_active,created_at) ON {s}.users FROM {api}')
    for table in ("auth_refresh_tokens", "auth_sessions", "auth_rate_limits"):
        op.drop_table(table)
